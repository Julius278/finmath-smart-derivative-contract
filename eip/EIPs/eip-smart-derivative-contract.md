---
eip: <to be assigned>
title: Smart Derivative Contract
description: A deterministic protocol for frictionless post-trade processing of OTC financial contracts
author: Christian Fries (@cfries), Peter Kohl-Landgraf (@pekola), Alexandros Korpis
discussions-to: https://ethereum-magicians.org/
status: Draft
type: Standard Track
category (*only required for Standards Track): ERC
created: 2022-11-21
requires (*optional): <EIP number(s)>
---

## Abstract
The Smart Derivative Contract is a deterministic protocol to trade and process 
financial derivative contracts frictionless and scalable in a complete automated way. Counterparty credit risk ís removed. 
Known operational risks and complexities in post-trade processing are removed by construction as all process states 
are fully specified and are known to the counterparties.

## Motivation
### Rethinking Financial Derivatives
By their very nature so-called "over-the-counter (OTC)" financial contracts are bilateral contractual agreements on the exchange of long-dated cash flow schedules.
Since these contracts change their intrinsic market value due to changing market environments they are subject to counterparty credit risk when one counterparty is subject to default.
The initial white paper describes the concept of a Smart Derivative Contract with the central aim 
to detach bilateral financial transactions from counterparty credit risk and to remove complexities 
in bilateral post-trade processing by a complete redesign.
https://papers.ssrn.com/sol3/papers.cfm?abstract_id=3249430

### Concept of a Smart Derivative Contract
A Smart Derivative Contract is a deterministic settlement protocol which has the same economical behaviour as a collateralized OTC
Derivative. Every process state is specified and therefore known in advance.
A Smart Derivative Contract (SDC) settles outstanding net present value of the underlying financial contract on a frequent basis. With each settlement cycle net present value of the underlying contract is
exchanged and the value of the contract is reset to zero. Pre-Agreed margin buffers are locked at the beginning of each settlement cycle such that settlement will be guaranteed up to a certain amount. 
In case a counterparty fails to obey contract rules, e.g. not provide sufficient prefunding, SDC will terminate automatically with the guaranteed transfer of a termination fee by the causing party.
These features enable two counterparties to process their financial contract fully decentralized without relying on a third central intermediary agent.
Process logic of SDC can be implemented as a finite state machine on solidity. ERC20 token standard can be used for frictionless decentralized settlement - see reference implementation.
Combined with an appropriate external market data and valuation oracle which calculates net present values, each known OTC derivative contract is able to be processed using this standard protocol.


## Specification

### Methods
The following methods specify  inception and post-trade live cycle of a Smart Derivative Contract. For futher information also please look at the interface documentation ISDC.sol.
#### inceptTrade
A counterparty can initiate a trade by providing trade data as string and calling inceptTrade and initial settlement data. Only registered counteparties are allowed to use that function.
``` js
function inceptTrade(string memory _tradeData, string memory _initialSettlementData) external
```
#### confirmTrade
A counterparty can confirm a trade by providing the identical trade data and initial settlement information which are already stored from inceptTrade call.

``` js
function confirmTrade(string memory _tradeData, string memory _initialSettlementData) external;
```

#### initiatePrefunding
This method checks whether contractual prefunding is provided by both counterparties as agreed in the contract terms. Triggers a contract termination if not. 
``` js
function initiatePrefunding() external;
```

#### initiateSettlement
Allowes eligible particiants - e.g. counterparties or a delegated agent - to initiate a settlement.
``` js
function initiateSettlement() external;
```

#### performSettlement
Valuation may be provided off-chain via an external oracle service with calculates net present value and uses external market data. 
Method serves as callback called from an external oracle providing settlement amount and used settlement data which also get stored.
Settlement amount will be checked according to contract terms resulting in either a reqular settlement or a termination of the trade.
``` js
function performSettlement(int256 settlementAmount, string memory settlementData) external;
```

#### requestTermination
Method enables an eligible party to request a mutual termination.
``` js
function requestTradeTermination(string memory tradeId) external;
```

#### confirmTradeTermination
With this method eligible party is allowed to confirm a former requested mutual trade termination
``` js
function confirmTradeTermination(string memory tradeId) external;
```

### Trade Events
The following events are emitted during a SDC trade livecycle.

#### TradeIncepted
Emitted on trade inception - method `inceptTrade`
``` js
event TradeIncepted(address initiator, string tradeId, string tradeData);
```

#### TradeConfirmed
Emitted on trade confirmation - method `confirmTrade`
``` js
event TradeConfirmed(address confirmer, string tradeId);
```

#### TradeActivated
Emitted when trade is activated
``` js
event TradeActivated(string tradeId);
```

#### TradeTerminationRequest
Emitted when termination request is initiated by a counterparty
``` js
event TradeTerminationRequest(address cpAddress, string tradeId);
```

#### TradeTerminationConfirmed
Emitted when termination request is confirmed by a counterparty
``` js
event TradeTerminationConfirmed(address cpAddress, string tradeId);
```

#### TradeTerminated
Emitted when trade is terminated
``` js
event TradeTerminated(string cause);
```

### Process Events
The following events are emitted during SDC's process live cycle.

#### ProcessAwaitingFunding
Emitted when funding phase is initiated
``` js
event ProcessAwaitingFunding();
```
#### ProcessFunded
Emitted when funding has completed successfully - method `initiatePrefunding`
``` js
event ProcessFunded();
```
#### ProcessSettlementRequest
Emitted when a settlement is initiated - method `initiateSettlement`
``` js
event ProcessSettled(string tradeData, string lastSettlementData);
```
#### ProcessSettled
Emitted when settlement was processed successfully - method 'performSettlement'
``` js
event ProcessSettled();
```

## Rationale
The interface design and reference implementation is based on following considerations:
- A SDC protocol is supposed to be used by two counterparties and enables them to initiate and process a derivative transaction in a bilateral and digital manner.
- Therefore contract interface specification is supposed to completely refelect the trade livecycle.
- The interface specification is generic enough to handle the case that two counterparties process one or even multible transactions (on a netted base)
- Usually the valuation of an OTC trade will require complex valuation methodology. Therefore the concept will in most cases rely on external market data and valuation algorithms
- A pull-based valuation based oracle pattern is specified by a simple callback pattern (methods: initiateSettlement, performSettlement)
- The reference implementation `SDC.sol` is based on a state-machine pattern where the states also serve as guards (via modifiers) to check which method is allowed to be called at a particular given process and trade state
- Java based state machine and contract implementations are also available. See github below.

## Test Cases
Live-cycle unit tests based on the sample implementation and usage of erc20 token is provided. See folder '/assets/test'.

## Reference Implementations
A reference implementation `SDC.sol` is provided based on ERC20 token standard. See folder '/assets/contracts'.

## Oracle Valuation Service Functionality
External Valuation Oracle functionality (java) is available on github:
`git clone https://github.com/finmath/finmath-smart-derivative-contract.git`


## Literature
- [Rethinking financial derivatives inspired by smart contracts (2018)](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=3249430)
- [Smart Derivative Contracts (2018)](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=3163074)
- [Constructing a digital financial derivative (2018)](https://blogs.law.ox.ac.uk/business-law-blog/blog/2018/12/smart-derivative-contract-constructing-digital-financial-derivative)
- [Implementing a financial derivative as smart contract (2019)](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=3342785)
- [Outsmarting counterparty credit risk (2020)](https://www.risk.net/cutting-edge/views/7494071/outsmarting-counterparty-risk-with-smart-contracts)

## Copyright
Copyright and related rights waived via ...

