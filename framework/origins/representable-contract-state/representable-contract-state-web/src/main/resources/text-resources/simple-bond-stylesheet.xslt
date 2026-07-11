<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet
    version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:s="urn:smart-product-framework:simple-bond:1.0">

    <xsl:output method="html" indent="yes" encoding="UTF-8"/>

    <xsl:template match="/">
        <html>
            <head>
                <title>Simple Bond - Smart Product Framework Demo</title>
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
                <h1>Simple Bond</h1>
                <p class="muted">
                    Smart Product Framework demo document rendered from on-chain state and XML terms.
                </p>

                <h2>Overview</h2>
                <table>
                    <tr>
                        <th>Product</th>
                        <td><xsl:value-of select="//s:ProductName"/></td>
                    </tr>
                    <tr>
                        <th>Instrument Type</th>
                        <td><xsl:value-of select="//s:InstrumentType"/></td>
                    </tr>
                    <tr>
                        <th>Currency</th>
                        <td><xsl:value-of select="//s:EconomicTerms/s:Currency"/></td>
                    </tr>
                </table>

                <h2>Negotiated Economic Terms</h2>
                <table>
                    <tr>
                        <th>Notional</th>
                        <td>
                            <xsl:value-of select="//s:Notional/s:Amount"/>
                            <xsl:text> </xsl:text>
                            <xsl:value-of select="//s:Notional/s:Currency"/>
                        </td>
                    </tr>
                    <tr>
                        <th>Maturity</th>
                        <td><xsl:value-of select="//s:MaturityDate/s:UnadjustedDate"/></td>
                    </tr>
                    <tr>
                        <th>Trade Status</th>
                        <td><xsl:value-of select="//s:TradeStatus"/></td>
                    </tr>
                </table>

                <h2>On-chain Context</h2>
                <table>
                    <tr>
                        <th>Trade ID</th>
                        <td class="mono"><xsl:value-of select="//s:TradeId"/></td>
                    </tr>
                    <tr>
                        <th>Product Provider</th>
                        <td class="mono"><xsl:value-of select="//s:ProductProvider"/></td>
                    </tr>
                    <tr>
                        <th>Investor</th>
                        <td class="mono"><xsl:value-of select="//s:Investor"/></td>
                    </tr>
                    <tr>
                        <th>Product Definition ID</th>
                        <td class="mono"><xsl:value-of select="//s:ProductDefinitionId"/></td>
                    </tr>
                    <tr>
                        <th>Product Definition Version</th>
                        <td><xsl:value-of select="//s:ProductDefinitionVersion"/></td>
                    </tr>
                    <tr>
                        <th>Product Type ID</th>
                        <td class="mono"><xsl:value-of select="//s:ProductTypeId"/></td>
                    </tr>
                    <tr>
                        <th>Deployment State Hash</th>
                        <td class="mono"><xsl:value-of select="//s:DeploymentStateHash"/></td>
                    </tr>
                </table>

                <h2>Lifecycle Notes</h2>
                <ul>
                    <li><xsl:value-of select="//s:Lifecycle/s:Requested"/></li>
                    <li><xsl:value-of select="//s:Lifecycle/s:Incepted"/></li>
                    <li><xsl:value-of select="//s:Lifecycle/s:Active"/></li>
                </ul>
            </body>
        </html>
    </xsl:template>
</xsl:stylesheet>
