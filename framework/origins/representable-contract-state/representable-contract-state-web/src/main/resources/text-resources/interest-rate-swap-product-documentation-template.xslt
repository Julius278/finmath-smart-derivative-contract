<?xml version="1.0" encoding="UTF-8"?>
<!-- Documentation view for the Smart Product Framework interest-rate-swap demo. -->
<xsl:stylesheet
    version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:spf="urn:smart-product-framework:interest-rate-swap:1.0"
    xmlns:fpml="http://www.fpml.org/FpML-5/confirmation"
    exclude-result-prefixes="spf fpml">

    <xsl:output method="html" indent="yes" encoding="UTF-8"/>

    <xsl:template match="/">
        <xsl:variable name="productState" select="/spf:InterestRateSwap"/>
        <xsl:variable name="deploymentState" select="$productState/spf:DeploymentState"/>
        <xsl:variable name="terms"
                      select="$productState/spf:ProductResources/spf:ProductTermsTemplate/spf:InterestRateSwapTerms
                            | $productState/spf:InterestRateSwapTerms"/>
        <xsl:variable name="confirmation" select="$terms/fpml:dataDocument"/>
        <xsl:variable name="trade" select="$confirmation/fpml:trade"/>
        <xsl:variable name="fixedLeg" select="$trade/fpml:swap/fpml:swapStream[@id='fixedLeg']"/>
        <xsl:variable name="floatingLeg" select="$trade/fpml:swap/fpml:swapStream[@id='floatingLeg']"/>
        <xsl:variable name="valuationInputs" select="$terms/spf:valuationInputs"/>
        <xsl:variable name="fixedRate"
                      select="$fixedLeg/fpml:calculationPeriodAmount/fpml:calculation/fpml:fixedRateSchedule/fpml:initialValue"/>
        <xsl:variable name="fixedNotional"
                      select="$fixedLeg/fpml:calculationPeriodAmount/fpml:calculation/fpml:notionalSchedule/fpml:notionalStepSchedule"/>

        <html>
            <head>
                <title>Interest Rate Swap - Smart Product Framework Demo</title>
                <style type="text/css">
                    body {
                        font-family: Arial, sans-serif;
                        margin: 2rem;
                        color: #1f2933;
                    }
                    h1 {
                        margin-bottom: 0.25rem;
                    }
                    h2 {
                        margin-top: 2rem;
                        border-bottom: 1px solid #d9e2ec;
                        padding-bottom: 0.25rem;
                    }
                    table {
                        border-collapse: collapse;
                        width: 100%;
                        margin-top: 0.75rem;
                    }
                    th, td {
                        border: 1px solid #d9e2ec;
                        padding: 0.5rem;
                        text-align: left;
                        vertical-align: top;
                    }
                    th {
                        width: 28%;
                        background: #f0f4f8;
                    }
                    .muted {
                        color: #627d98;
                    }
                    .mono {
                        font-family: Consolas, monospace;
                        word-break: break-all;
                    }
                </style>
            </head>
            <body>
                <h1>Fixed-Floating Interest Rate Swap</h1>
                <p class="muted">
                    Lightweight FpML-aligned confirmation rendered from the deployed product's on-chain state.
                </p>

                <h2>Lifecycle</h2>
                <table>
                    <tr>
                        <th>Status</th>
                        <td>
                            <xsl:choose>
                                <xsl:when test="$deploymentState/spf:TradeStatus = '0'">Requested</xsl:when>
                                <xsl:when test="$deploymentState/spf:TradeStatus = '1'">Incepted</xsl:when>
                                <xsl:when test="$deploymentState/spf:TradeStatus = '2'">Active</xsl:when>
                                <xsl:when test="$deploymentState/spf:TradeStatus = '3'">Cancelled</xsl:when>
                                <xsl:otherwise>Unknown</xsl:otherwise>
                            </xsl:choose>
                            <xsl:text> (</xsl:text>
                            <xsl:value-of select="$deploymentState/spf:TradeStatus"/>
                            <xsl:text>)</xsl:text>
                        </td>
                    </tr>
                    <tr>
                        <th>Trade ID</th>
                        <td class="mono"><xsl:value-of select="$trade/fpml:tradeHeader/fpml:partyTradeIdentifier/fpml:tradeId"/></td>
                    </tr>
                    <tr>
                        <th>Trade date</th>
                        <td><xsl:value-of select="$trade/fpml:tradeHeader/fpml:tradeDate"/></td>
                    </tr>
                </table>

                <h2>Economic Terms</h2>
                <table>
                    <tr>
                        <th>Notional</th>
                        <td>
                            <xsl:value-of select="$fixedNotional/fpml:initialValue"/>
                            <xsl:text> </xsl:text>
                            <xsl:value-of select="$fixedNotional/fpml:currency"/>
                        </td>
                    </tr>
                    <tr>
                        <th>Effective date</th>
                        <td><xsl:value-of select="$fixedLeg/fpml:calculationPeriodDates/fpml:effectiveDate/fpml:unadjustedDate"/></td>
                    </tr>
                    <tr>
                        <th>Maturity</th>
                        <td><xsl:value-of select="$fixedLeg/fpml:calculationPeriodDates/fpml:terminationDate/fpml:unadjustedDate"/></td>
                    </tr>
                    <tr>
                        <th>Fixed swap rate</th>
                        <td>
                            <xsl:value-of select="$fixedRate"/>
                            <xsl:text> decimal (</xsl:text>
                            <xsl:value-of select="format-number(number($fixedRate) * 100, '0.####')"/>
                            <xsl:text>%)</xsl:text>
                        </td>
                    </tr>
                    <tr>
                        <th>Fixed leg convention</th>
                        <td>
                            <xsl:value-of select="$fixedLeg/fpml:calculationPeriodAmount/fpml:calculation/fpml:dayCountFraction"/>
                            <xsl:text>; </xsl:text>
                            <xsl:value-of select="$fixedLeg/fpml:calculationPeriodDates/fpml:calculationPeriodFrequency/fpml:periodMultiplier"/>
                            <xsl:value-of select="$fixedLeg/fpml:calculationPeriodDates/fpml:calculationPeriodFrequency/fpml:period"/>
                        </td>
                    </tr>
                    <tr>
                        <th>Floating leg</th>
                        <td>
                            <xsl:value-of select="normalize-space($floatingLeg/fpml:calculationPeriodAmount/fpml:calculation/fpml:floatingRateCalculation/fpml:floatingRateIndex)"/>
                            <xsl:text> </xsl:text>
                            <xsl:value-of select="$floatingLeg/fpml:calculationPeriodAmount/fpml:calculation/fpml:floatingRateCalculation/fpml:indexTenor/fpml:periodMultiplier"/>
                            <xsl:value-of select="$floatingLeg/fpml:calculationPeriodAmount/fpml:calculation/fpml:floatingRateCalculation/fpml:indexTenor/fpml:period"/>
                            <xsl:text>; </xsl:text>
                            <xsl:value-of select="$floatingLeg/fpml:calculationPeriodAmount/fpml:calculation/fpml:dayCountFraction"/>
                        </td>
                    </tr>
                </table>

                <h2>Parties and Fixed-Rate Role</h2>
                <table>
                    <tr>
                        <th>Client fixed-rate role</th>
                        <td><xsl:value-of select="$valuationInputs/spf:clientFixedRateRole"/></td>
                    </tr>
                    <tr>
                        <th>Fixed-rate payer</th>
                        <td><xsl:value-of select="$fixedLeg/fpml:payerPartyReference/@href"/></td>
                    </tr>
                    <tr>
                        <th>Fixed-rate receiver</th>
                        <td><xsl:value-of select="$fixedLeg/fpml:receiverPartyReference/@href"/></td>
                    </tr>
                    <tr>
                        <th>Client</th>
                        <td class="mono"><xsl:value-of select="$confirmation/fpml:party[@id='client']/fpml:partyId"/></td>
                    </tr>
                    <tr>
                        <th>Product provider</th>
                        <td class="mono"><xsl:value-of select="$confirmation/fpml:party[@id='productProvider']/fpml:partyId"/></td>
                    </tr>
                </table>

                <h2>Valuation Inputs</h2>
                <p class="muted">
                    These symbolic assignments are Smart Product Framework extensions and are intentionally kept outside the FpML confirmation.
                </p>
                <table>
                    <tr>
                        <th>Forward curve</th>
                        <td class="mono"><xsl:value-of select="$valuationInputs/spf:forwardCurveSymbol"/></td>
                    </tr>
                    <tr>
                        <th>Discount curve</th>
                        <td class="mono"><xsl:value-of select="$valuationInputs/spf:discountCurveSymbol"/></td>
                    </tr>
                </table>
            </body>
        </html>
    </xsl:template>
</xsl:stylesheet>
