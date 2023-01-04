package net.finmath.smartcontract.oracle.interestrates;

import net.finmath.marketdata.model.AnalyticModel;
import net.finmath.marketdata.products.Swap;
import net.finmath.marketdata.products.SwapLeg;
import net.finmath.smartcontract.oracle.ValuationOracle;
import net.finmath.smartcontract.marketdata.curvecalibration.CalibrationContextImpl;
import net.finmath.smartcontract.marketdata.curvecalibration.CalibrationParserDataPoints;
import net.finmath.smartcontract.marketdata.curvecalibration.CalibrationResult;
import net.finmath.smartcontract.marketdata.curvecalibration.Calibrator;
import net.finmath.smartcontract.marketdata.util.IRMarketDataSet;
import org.javamoney.moneta.Money;

import javax.money.CurrencyUnit;
import javax.money.Monetary;
import javax.money.MonetaryAmount;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

/**
 * An oracle for swap valuation which generates values using externally provided historical market data scenarios.
 *
 * @author Peter Kohl-Landgraf
 * @author Christian Fries
 */

public class ValuationOraclePlainSwap implements ValuationOracle {

	private final CurrencyUnit currency = Monetary.getCurrency("EUR");
	private final List<IRMarketDataSet> scenarioList;
	private final Swap product;
	private final LocalDate productStartDate;
	private final double notionalAmount;

	/**
	 * Oracle will be instantiated based on a Swap product an market data scenario list
	 *
	 * @param product        The underlying swap product.
	 * @param notionalAmount The notional of the product.
	 * @param scenarioList   The list of market data scenarios to be used for valuation.
	 */
	public ValuationOraclePlainSwap(final Swap product, final double notionalAmount, final List<IRMarketDataSet> scenarioList) {
		this.notionalAmount = notionalAmount;
		this.product = product;
		this.productStartDate = ((SwapLeg) this.product.getLegPayer()).getSchedule().getReferenceDate();
		this.scenarioList = scenarioList;
	}

	@Override
	public MonetaryAmount getAmount(final LocalDateTime evaluationTime, final LocalDateTime marketDataTime) {
		return Money.of(getValue(evaluationTime, marketDataTime), currency);
	}

	@Override
	public Double getValue(final LocalDateTime evaluationDate, final LocalDateTime marketDataTime) {
		final Optional<IRMarketDataSet> optionalScenario = scenarioList.stream().filter(scenario -> scenario.getDate().equals(marketDataTime)).findAny();
		if (optionalScenario.isPresent()) {
			final IRMarketDataSet scenario = optionalScenario.get();
			final CalibrationParserDataPoints parser = new CalibrationParserDataPoints();
			final Calibrator calibrator = new Calibrator();
			try {
				final Optional<CalibrationResult> optionalCalibrationResult = calibrator.calibrateModel(scenario.getDataAsCalibrationDataPointStream(parser), new CalibrationContextImpl(marketDataTime.toLocalDate(), 1E-6));
				AnalyticModel calibratedModel = optionalCalibrationResult.get().getCalibratedModel();

				final double evaluationTime = 0.0;    // Time relative to models reference date (which agrees with evaluationDate).
				final double valueWithCurves = product.getValue(evaluationTime, calibratedModel) * notionalAmount;
				calibratedModel = null;
				return valueWithCurves;
			} catch (final Exception e) {
				return null;
			}
		} else {
			return null;
		}
	}
}
