package net.finmath.smartcontract.valuation.service.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;


@Configuration
@ConfigurationProperties(prefix = "valuation")
public class ValuationConfig {
	private boolean liveMarketData;
	private String settlementCurrency;
	private String liveMarketDataProvider;

	public boolean isLiveMarketData() {
		return liveMarketData;
	}

	public void setLiveMarketData(boolean liveMarketData) {
		this.liveMarketData = liveMarketData;
	}

	public String getSettlementCurrency() {
		return settlementCurrency;
	}

	public void setSettlementCurrency(String settlementCurrency) {
		this.settlementCurrency = settlementCurrency;
	}

	public String getLiveMarketDataProvider() {
		return liveMarketDataProvider;
	}

	public void setLiveMarketDataProvider(String liveMarketDataProvider) {
		this.liveMarketDataProvider = liveMarketDataProvider;
	}
}