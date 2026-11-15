// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {
    ClientRegistry
} from "../contracts/examples/SmartProductFramework/ClientRegistry/ClientRegistry.sol";
import {
    IClientRegistry
} from "../contracts/examples/SmartProductFramework/ClientRegistry/IClientRegistry.sol";
import {
    ProductDefinitionRegistry
} from "../contracts/examples/SmartProductFramework/ProductRegistry/ProductDefinitionRegistry.sol";
import {
    IProductDefinitionRegistry
} from "../contracts/examples/SmartProductFramework/ProductRegistry/IProductDefinitionRegistry.sol";
import {
    SimpleBond
} from "../contracts/examples/SmartProductFramework/SimpleBondDemo/SimpleBond.sol";
import {
    SimpleBondFactory
} from "../contracts/examples/SmartProductFramework/SimpleBondDemo/SimpleBondFactory.sol";
import {
    CurveIndications
} from "../contracts/examples/SmartProductFramework/SimpleBondDemo/CurveIndications.sol";
import {
    InterestRateSwap
} from "../contracts/examples/SmartProductFramework/InterestRateSwapDemo/InterestRateSwap.sol";
import {
    InterestRateSwapFactory
} from "../contracts/examples/SmartProductFramework/InterestRateSwapDemo/InterestRateSwapFactory.sol";
import {
    IProductFactory
} from "../contracts/examples/SmartProductFramework/ProductFactory/IProductFactory.sol";
import {
    AbstractProductFactory
} from "../contracts/examples/SmartProductFramework/ProductFactory/AbstractProductFactory.sol";
import {
    ProductDeploymentParams
} from "../contracts/examples/SmartProductFramework/ProductFactory/ProductDeploymentTypes.sol";
import {
    ITradeLifecycle
} from "../contracts/examples/SmartProductFramework/Product/ITradeLifecycle.sol";
import {TextResource} from "../contracts/resources/TextResource.sol";

/// @dev Only the Foundry cheatcodes needed by this self-contained suite.
interface Vm {
    function prank(address sender) external;
    function expectRevert(bytes calldata reason) external;
    function readFile(string calldata path) external view returns (string memory);
    function getCode(string calldata artifactPath) external view returns (bytes memory);
}

contract OriginalProductsTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant CLIENT = address(0xBEEF);
    address private constant OUTSIDER = address(0xBAD);
    ClientRegistry private clients;
    ProductDefinitionRegistry private registry;
    CurveIndications private curves;
    SimpleBondFactory private bondFactory;
    InterestRateSwapFactory private swapFactory;
    bytes32 private bondDefinition;
    bytes32 private swapDefinition;
    bytes32 private curveId;
    TextResource private bondTerms;
    TextResource private swapTerms;

    function setUp() public {
        clients =
            ClientRegistry(_deploy("ClientRegistry.sol:ClientRegistry", abi.encode(address(this))));
        registry = ProductDefinitionRegistry(
            _deploy(
                "ProductDefinitionRegistry.sol:ProductDefinitionRegistry",
                abi.encode(address(this), address(clients))
            )
        );
        curves = CurveIndications(
            _deploy("CurveIndications.sol:CurveIndications", abi.encode(address(this)))
        );
        bondFactory = SimpleBondFactory(
            _deploy(
                "SimpleBondFactory.sol:SimpleBondFactory",
                abi.encode(address(registry), address(curves))
            )
        );
        swapFactory = InterestRateSwapFactory(
            _deploy(
                "InterestRateSwapFactory.sol:InterestRateSwapFactory", abi.encode(address(registry))
            )
        );
        clients.registerClient(
            IClientRegistry.ClientRegistrationParams(CLIENT, "00000000000000000098")
        );
        (bondDefinition, bondTerms) =
            _publish("SimpleBond", IProductFactory(address(bondFactory)), "simple-bond", true);
        (swapDefinition, swapTerms) = _publish(
            "InterestRateSwap", IProductFactory(address(swapFactory)), "interest-rate-swap", false
        );
        CurveIndications.QuoteParams[] memory quotes = new CurveIndications.QuoteParams[](1);
        quotes[0] = CurveIndications.QuoteParams(
            "ONE_YEAR",
            365,
            block.timestamp + 1 days,
            block.timestamp + 366 days,
            "ACT/365",
            250,
            "EUR",
            250,
            100_000_000,
            100_000_000,
            1_000,
            1_000_000
        );
        curveId = curves.publishCurveIndications("Demo EUR", quotes);
        registry.setProductIndication(bondDefinition, address(curves), curveId);
    }

    function testSimpleBondRegistryFactoryAndLifecycle() public {
        (bytes32 tradeId, address product) =
            _request(bondDefinition, abi.encode(uint256(100_000), block.timestamp + 365 days));
        SimpleBond bond = SimpleBond(product);
        require(registry.productOf(tradeId) == product, "registry product");
        require(bondFactory.isFactoryDeployedProduct(product), "factory provenance");
        require(
            bond.productFactory() == address(bondFactory)
                && bond.productRegistry() == address(registry),
            "deployment anchors"
        );
        require(bond.client() == CLIENT && bond.productProvider() == address(this), "trade parties");
        require(
            bond.productDefinitionId() == bondDefinition && bond.tradeId() == tradeId,
            "trade identity"
        );
        bytes32 originalHash = bond.currentTermsHash();
        vm.prank(CLIENT);
        bond.updateTerms(abi.encode(uint256(120_000), block.timestamp + 400 days));
        require(
            bond.notional() == 120_000 && bond.maturity() == block.timestamp + 400 days,
            "updated bond terms"
        );
        require(bond.currentTermsHash() != originalHash, "terms hash must change");
        _activate(ITradeLifecycle(product));
        require(
            uint256(bond.tradeStatus()) == uint256(ITradeLifecycle.TradeStatus.Active),
            "active bond"
        );
    }

    function testInterestRateSwapRegistryFactoryAndLifecycle() public {
        (bytes32 tradeId, address product) = _request(swapDefinition, _swapPayload(250, 0));
        InterestRateSwap swap = InterestRateSwap(product);
        require(
            registry.productOf(tradeId) == product && swapFactory.isFactoryDeployedProduct(product),
            "registered swap"
        );
        require(swap.notional() == 100_000_000 && swap.swapRate() == 250, "initial swap terms");
        require(
            keccak256(bytes(swap.fixedLegPayerPartyReference())) == keccak256("client"),
            "payer role"
        );
        uint256 tradeDate = swap.tradeDate();
        vm.prank(CLIENT);
        swap.updateTerms(_swapPayload(275, 1));
        require(
            swap.swapRate() == 275 && swap.tradeDate() == tradeDate,
            "updated rate preserves trade date"
        );
        require(
            keccak256(bytes(swap.fixedLegPayerPartyReference())) == keccak256("productProvider"),
            "receiver role"
        );
        require(
            keccak256(bytes(swap.floatingLegPayerPartyReference())) == keccak256("client"),
            "floating role"
        );
        _activate(ITradeLifecycle(product));
        require(
            uint256(swap.tradeStatus()) == uint256(ITradeLifecycle.TradeStatus.Active),
            "active swap"
        );
    }

    function testBothProductsExposeOriginalTemplatesAndDeploymentBindings() public {
        (, address bond) =
            _request(bondDefinition, abi.encode(uint256(100_000), block.timestamp + 365 days));
        (, address swap) = _request(swapDefinition, _swapPayload(250, 0));
        require(_contains(SimpleBond(bond).stateXmlTemplate(), "<SimpleBond"), "bond envelope");
        require(
            _contains(InterestRateSwap(swap).stateXmlTemplate(), "<InterestRateSwap"),
            "swap envelope"
        );
        require(
            _contains(SimpleBond(bond).stateXmlTemplate(), bondTerms.web3Url()),
            "bond terms include"
        );
        require(
            _contains(InterestRateSwap(swap).stateXmlTemplate(), swapTerms.web3Url()),
            "swap terms include"
        );
        require(
            _contains(SimpleBond(bond).stateXmlTemplate(), "evmstate:integrity=\"keccak256-"),
            "resource integrity"
        );
        require(
            _contains(InterestRateSwap(swap).stateXmlTemplate(), "tradeStatus()(uint8)"),
            "lifecycle binding"
        );
        require(
            _contains(registry.statePartXmlTemplate(uint256(bondDefinition)), "ProductDefinition"),
            "definition representation"
        );
        require(
            _contains(curves.statePartXmlTemplate(uint256(curveId)), "activeQuotesByPartId"),
            "curve representation"
        );
    }

    function testOriginalResourcesAreFinalizedAndHashVerified() public view {
        bytes memory bondSource =
            bytes(vm.readFile("resources/simple-bond-product-terms-template.xml"));
        bytes memory swapSource =
            bytes(vm.readFile("resources/interest-rate-swap-product-terms-template.xml"));
        require(bondTerms.isFinalized() && swapTerms.isFinalized(), "resources finalized");
        require(bondTerms.contentHash() == keccak256(bondSource), "staged bond resource hash");
        require(swapTerms.contentHash() == keccak256(swapSource), "one-shot swap resource hash");
        require(keccak256(bondTerms.content()) == keccak256(bondSource), "bond resource content");
        require(keccak256(swapTerms.content()) == keccak256(swapSource), "swap resource content");
    }

    function testEligibilityAppliesToBothProductFactories() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ProductDefinitionRegistry.ClientNotEligible.selector, OUTSIDER, bondDefinition
            )
        );
        vm.prank(OUTSIDER);
        registry.createTradeRequest(
            ProductDefinitionRegistry.TradeRequestParams(
                bondDefinition, abi.encode(uint256(100), block.timestamp + 1 days)
            )
        );
        clients.setClientStatus(CLIENT, IClientRegistry.ClientStatus.Suspended);
        vm.expectRevert(
            abi.encodeWithSelector(
                ProductDefinitionRegistry.ClientNotEligible.selector, CLIENT, swapDefinition
            )
        );
        vm.prank(CLIENT);
        registry.createTradeRequest(
            ProductDefinitionRegistry.TradeRequestParams(swapDefinition, _swapPayload(250, 0))
        );
    }

    function testFactoryRejectsDeploymentOutsideRegistry() public {
        ProductDeploymentParams memory params;
        vm.expectRevert(
            abi.encodeWithSelector(
                AbstractProductFactory.NotProductRegistry.selector, address(this)
            )
        );
        bondFactory.deployProduct(params);
        vm.expectRevert(
            abi.encodeWithSelector(
                AbstractProductFactory.NotProductRegistry.selector, address(this)
            )
        );
        swapFactory.deployProduct(params);
    }

    function testTradeHashAgreementAndPartyAuthorization() public {
        (, address product) = _request(swapDefinition, _swapPayload(250, 0));
        ITradeLifecycle swap = ITradeLifecycle(product);
        bytes32 terms = swap.currentTermsHash();
        vm.expectRevert(
            abi.encodeWithSelector(ITradeLifecycle.NotProductProvider.selector, OUTSIDER)
        );
        vm.prank(OUTSIDER);
        swap.inceptTrade(terms);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITradeLifecycle.AgreedTermsMismatch.selector, terms, bytes32(uint256(1))
            )
        );
        swap.inceptTrade(bytes32(uint256(1)));
        swap.inceptTrade(terms);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITradeLifecycle.AgreedTermsMismatch.selector, terms, bytes32(uint256(2))
            )
        );
        vm.prank(CLIENT);
        swap.confirmTrade(bytes32(uint256(2)));
        vm.expectRevert(
            abi.encodeWithSelector(
                ITradeLifecycle.InvalidTradeStatus.selector, ITradeLifecycle.TradeStatus.Incepted
            )
        );
        vm.prank(CLIENT);
        swap.updateTerms(_swapPayload(300, 0));
        vm.prank(CLIENT);
        swap.confirmTrade(terms);
        require(swap.agreedTermsHash() == terms, "agreed terms");
    }

    function testEitherPartyCanCancelBeforeActivation() public {
        (, address bond) =
            _request(bondDefinition, abi.encode(uint256(100), block.timestamp + 1 days));
        ITradeLifecycle(bond).cancelTrade();
        require(
            uint256(ITradeLifecycle(bond).tradeStatus())
                == uint256(ITradeLifecycle.TradeStatus.Cancelled),
            "requested bond cancellation"
        );
        (, address swap) = _request(swapDefinition, _swapPayload(250, 0));
        bytes32 terms = ITradeLifecycle(swap).currentTermsHash();
        ITradeLifecycle(swap).inceptTrade(terms);
        vm.prank(CLIENT);
        ITradeLifecycle(swap).cancelTrade();
        require(
            uint256(ITradeLifecycle(swap).tradeStatus())
                == uint256(ITradeLifecycle.TradeStatus.Cancelled),
            "incepted swap cancellation"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                ITradeLifecycle.InvalidTradeStatus.selector, ITradeLifecycle.TradeStatus.Cancelled
            )
        );
        vm.prank(CLIENT);
        ITradeLifecycle(swap).confirmTrade(terms);
    }

    function testTermsValidationRejectsInvalidBondAndSwap() public {
        vm.expectRevert(abi.encodeWithSelector(SimpleBond.InvalidNotional.selector));
        vm.prank(CLIENT);
        registry.createTradeRequest(
            ProductDefinitionRegistry.TradeRequestParams(
                bondDefinition, abi.encode(uint256(0), block.timestamp + 1 days)
            )
        );
        vm.expectRevert(
            abi.encodeWithSelector(InterestRateSwap.InvalidFixedRateRole.selector, uint8(2))
        );
        vm.prank(CLIENT);
        registry.createTradeRequest(
            ProductDefinitionRegistry.TradeRequestParams(swapDefinition, _swapPayload(250, 2))
        );
    }

    function testTradeRequestsHaveIndependentIdentityAndTermsHashes() public {
        bytes memory payload = abi.encode(uint256(100), block.timestamp + 1 days);
        (bytes32 trade1, address first) = _request(bondDefinition, payload);
        (bytes32 trade2, address second) = _request(bondDefinition, payload);
        require(trade1 != trade2 && first != second, "distinct trades");
        require(
            ITradeLifecycle(first).currentTermsHash() != ITradeLifecycle(second).currentTermsHash(),
            "hash bound to deployment"
        );
        require(
            SimpleBond(first).deploymentStateHash() != SimpleBond(second).deploymentStateHash(),
            "independent deployment state"
        );
    }

    function testDeployableContractsStayWithinRuntimeLimit() public view {
        require(address(registry).code.length <= 24_576, "registry runtime limit");
        require(address(bondFactory).code.length <= 24_576, "bond factory runtime limit");
        require(address(swapFactory).code.length <= 24_576, "swap factory runtime limit");
        require(address(curves).code.length <= 24_576, "curve runtime limit");
    }

    function _request(bytes32 definition, bytes memory payload)
        private
        returns (bytes32 trade, address product)
    {
        vm.prank(CLIENT);
        return registry.createTradeRequest(
            ProductDefinitionRegistry.TradeRequestParams(definition, payload)
        );
    }

    function _activate(ITradeLifecycle product) private {
        bytes32 terms = product.currentTermsHash();
        product.inceptTrade(terms);
        vm.prank(CLIENT);
        product.confirmTrade(terms);
    }

    function _swapPayload(int256 rate, uint8 role) private view returns (bytes memory) {
        return abi.encode(
            InterestRateSwap.InterestRateSwapDeploymentPayload(
                100_000_000, "EUR", block.timestamp + 365 days, rate, role, "EURIBOR6M", "ESTR"
            )
        );
    }

    function _publish(
        string memory name,
        IProductFactory factory,
        string memory prefix,
        bool staged
    ) private returns (bytes32 definition, TextResource terms) {
        terms = _resource(
            factory.productTermsTemplateResourceType(),
            string.concat(prefix, "-product-terms-template.xml"),
            "application/xml",
            staged
        );
        TextResource documentation = _resource(
            factory.productDocumentationTemplateResourceType(),
            string.concat(prefix, "-product-documentation-template.xslt"),
            "application/xslt+xml",
            staged
        );
        definition = registry.publishProductDefinition(
            IProductDefinitionRegistry.ProductDefinitionPublicationParams(
                name,
                IProductDefinitionRegistry.ProductDefinition(
                    address(factory), address(terms), address(documentation)
                )
            )
        );
    }

    function _resource(bytes32 kind, string memory filename, string memory mediaType, bool staged)
        private
        returns (TextResource resource)
    {
        bytes memory content = bytes(vm.readFile(string.concat("resources/", filename)));
        bytes32 hash = keccak256(content);
        resource = TextResource(
            _deploy(
                "TextResource.sol:TextResource",
                abi.encode(address(this), kind, mediaType, staged ? bytes("") : content, hash)
            )
        );
        if (staged) {
            resource.appendChunkAt(0, content);
            resource.finalize(hash);
        }
    }

    function _deploy(string memory artifact, bytes memory args) private returns (address deployed) {
        bytes memory initcode = abi.encodePacked(vm.getCode(artifact), args);
        assembly ("memory-safe") { deployed := create(0, add(initcode, 32), mload(initcode)) }
        require(deployed != address(0), "fixture deployment failed");
    }

    function _contains(string memory haystack, string memory needle) private pure returns (bool) {
        bytes memory source = bytes(haystack);
        bytes memory sought = bytes(needle);
        if (sought.length > source.length) return false;
        for (uint256 i; i <= source.length - sought.length; ++i) {
            bool matches = true;
            for (uint256 j; j < sought.length; ++j) {
                if (source[i + j] != sought[j]) matches = false;
                break;
            }
            if (matches) return true;
        }
        return false;
    }
}
