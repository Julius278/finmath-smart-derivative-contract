package net.finmath.smartcontract.valuation.implementation;

import jakarta.xml.bind.JAXBContext;
import jakarta.xml.bind.JAXBElement;
import jakarta.xml.bind.Unmarshaller;
import net.finmath.smartcontract.product.xml.Document;
import net.finmath.smartcontract.valuation.client.ValuationClient;
import net.finmath.smartcontract.model.MarginResult;
import net.finmath.smartcontract.model.ValueResult;
import net.finmath.smartcontract.valuation.marketdata.data.MarketDataList;
import org.assertj.core.util.Files;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.api.Test;

import java.io.FileInputStream;
import java.io.FileReader;
import java.io.InputStreamReader;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.nio.file.Paths;

public class MarginCalculatorTest {

	@Test
	void testMargin() throws Exception {
		final String marketDataStart = new String(ValuationClient.class.getClassLoader().getResourceAsStream("net/finmath/smartcontract/valuation/client/md_testset1.xml").readAllBytes(), StandardCharsets.UTF_8);
		final String marketDataEnd = new String(ValuationClient.class.getClassLoader().getResourceAsStream("net/finmath/smartcontract/valuation/client/md_testset2.xml").readAllBytes(), StandardCharsets.UTF_8);
		final String product = new String(ValuationClient.class.getClassLoader().getResourceAsStream("net.finmath.smartcontract.product.xml/smartderivativecontract.xml").readAllBytes(), StandardCharsets.UTF_8);

		MarginCalculator marginCalculator = new MarginCalculator();
		MarginResult valuationResult = marginCalculator.getValue(marketDataStart, marketDataEnd, product);

		double value = valuationResult.getValue().doubleValue();

		Assertions.assertEquals(9908.52, value, 0.005, "Margin");
		System.out.println(valuationResult);
	}

	@Test
	void testValue() throws Exception {
		final String marketData = new String(ValuationClient.class.getClassLoader().getResourceAsStream("net/finmath/smartcontract/valuation/client/md_testset1.xml").readAllBytes(), StandardCharsets.UTF_8);
		final String product = new String(ValuationClient.class.getClassLoader().getResourceAsStream("net.finmath.smartcontract.product.xml/smartderivativecontract.xml").readAllBytes(), StandardCharsets.UTF_8);

		MarginCalculator marginCalculator = new MarginCalculator();
		ValueResult valuationResult = marginCalculator.getValue(marketData, product);

		double value = valuationResult.getValue().doubleValue();

		Assertions.assertEquals(926403.97, value, 0.005, "Valuation");
		System.out.println(valuationResult);
	}

}
