/*
 /*
 * (c) Copyright Christian P. Fries, Germany. Contact: email@christianfries.com.
 *
 * Created on 15 Oct 2018
 */

package net.finmath.smartcontract.service;

import net.finmath.smartcontract.api.SettlementValuationApi;
import net.finmath.smartcontract.util.SDCConstants;
import net.finmath.smartcontract.util.SDCDateUtil;
import net.finmath.smartcontract.util.SDCProperties;
import net.finmath.smartcontract.valuation.MarginCalculator;
import net.finmath.time.businessdaycalendar.BusinessdayCalendarExcludingTARGETHolidays;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.time.LocalDate;
import java.util.HashMap;

/**
 * Controller for the settlement valuation REST service.
 * TODO Refactor try/catch once openapi can generate exception handling
 * @author Christian Fries
 * @author Peter Kohl-Landgraf
 * @author Dietmar Schnabel
 */
@RestController
public class SettlementValuationController implements SettlementValuationApi {
	
	private  static String curve1 = "NONE";
	private  static String curve2 = "NONE";
	private  static final HashMap<String, String> fpml = new HashMap<String, String>();
	private  static final HashMap<String, String> result = new HashMap<String, String>();
	
	private final Logger logger = LoggerFactory.getLogger(SettlementValuationController.class);
	
	/**
	 * Request mapping for the settlementvaluationForProductAsFPML
	 * 
	 * @param tradeAsFPML Trade FPML string
	 * @param tradeId Trade ID
	 * @param marketDataAsJson1 Market data Json string
	 * @param marketDataAsJson2 Market data Json string
	 * @return String Json representing the valuation.
	 */
	public ResponseEntity<String> settlementvaluationForProductAsFPMLOnChain(String marketDataAsJson1, String marketDataAsJson2, String tradeAsFPML, String tradeId)
		{
		LocalDate ld1 = SDCDateUtil.getDateFromJSON(marketDataAsJson1, SDCConstants.DATE_FORMAT_yyyyMMdd);
		LocalDate ld2 = SDCDateUtil.getDateFromJSON(marketDataAsJson2, SDCConstants.DATE_FORMAT_yyyyMMdd);
		
		HttpHeaders responseHeaders = new HttpHeaders();
		responseHeaders.add("Responded", "SettlementValuationControllerTwoCurves");
		
		boolean b = true;
		if (SDCProperties.getProperty(SDCConstants.USE_CURVES_STRICT_BUS_DAYS).equals("TRUE")) {
			b = SDCDateUtil.isFollowingBusinessDays(ld1, ld2, new BusinessdayCalendarExcludingTARGETHolidays());
		}
		
		if(!b) {
			String message = "The dates " + ld1 + " and  " + ld2 + " are not T, T-1 following business dates!";
			logger.error(message);
			return new ResponseEntity<String>(message, responseHeaders, HttpStatus.BAD_REQUEST);
		}
		logger.info("Starting Margin Calculation with dates " + ld1 + " and  " + ld2);
		MarginCalculator marginCalculator = new MarginCalculator();
				
		double margin;
		try {
			marginCalculator.getValue(marketDataAsJson1, marketDataAsJson2, tradeAsFPML);
		} catch (Exception e) {
			logger.error("Failed to calculate margin.");
			e.printStackTrace();
		}
		if (logger.isDebugEnabled()) {
			logger.debug("json1bytes: " + marketDataAsJson1);
			logger.debug("json2bytes: " + marketDataAsJson2);
			logger.debug("fpmlbytes: " + tradeAsFPML);			
		}
		String resultJSON = marginCalculator.getContractValuationAsJSON();
		logger.info(resultJSON);
		curve1 = marketDataAsJson1;
		curve2 = marketDataAsJson2;
		fpml.put(tradeId, tradeAsFPML);
		result.put(tradeId, resultJSON);
		
		return new ResponseEntity<String>(resultJSON, responseHeaders, HttpStatus.OK);
	}
	
	/**
	 * Request mapping for the settlementvaluationForProductAsFPMLOneCurve
	 * 
	 * @param tradeAsFPML Trade FPML file
	 * @param marketDataAsJson1 Market data Json file1
	 * @return String Json representing the valuation.
	 */
	public ResponseEntity<String> settlementvaluationForProductAsFPMLOneCurve(MultipartFile marketDataAsJson1, MultipartFile tradeAsFPML)
		{
		
		HttpHeaders responseHeaders = new HttpHeaders();
		responseHeaders.add("Responded", "SettlementValuationControllerOneCurve");

			String json1String = null;
			try {
				json1String = new String(marketDataAsJson1.getBytes());
			} catch (IOException e) {
				throw new RuntimeException(e);
			}
			LocalDate ld1 = SDCDateUtil.getDateFromJSON(json1String, SDCConstants.DATE_FORMAT_yyyyMMdd);
		String currentDateString = SDCDateUtil.getStringFromDate(ld1, SDCConstants.DATE_FORMAT_yyyyMMdd);
		
		LocalDate previousDate = SDCDateUtil.getPreviousBusinessDay(ld1, new BusinessdayCalendarExcludingTARGETHolidays());
		logger.info("T-1 = " + previousDate);
		
		String previousDateString = SDCDateUtil.getStringFromDate(previousDate, SDCConstants.DATE_FORMAT_yyyyMMdd);
		String FileHeader = SDCProperties.getProperty(SDCConstants.DATA_PATH) + File.separator + SDCProperties.getProperty(SDCConstants.MARKET_DATA_FILE_HEADER);
		String previousJson = FileHeader + previousDateString + ".json";
		String currentJson = FileHeader + currentDateString + ".json";
		
		File previousFile = new File(previousJson);
		File currentFile = new File(currentJson);
		
		if(!Files.exists(previousFile.toPath())) {
			String message = "The file " + previousJson + " does not exist!";
			logger.error(message);
			return new ResponseEntity<String>(message, responseHeaders, HttpStatus.BAD_REQUEST);
		}
		logger.info("Previous File = " + previousFile);
			String json2String = null;
			try {
				json2String = new String(Files.readAllBytes(previousFile.toPath()));
			} catch (IOException e) {
				throw new RuntimeException(e);
			}
			LocalDate ld2 = SDCDateUtil.getDateFromJSON(json2String, SDCConstants.DATE_FORMAT_yyyyMMdd);


			String fpmlString = null;
			try {
				fpmlString = new String(tradeAsFPML.getBytes());
			} catch (IOException e) {
				throw new RuntimeException(e);
			}

			logger.info("Starting Margin Calculation with dates " + ld1 + " and  " + ld2);
		MarginCalculator marginCalculator = new MarginCalculator();
		
		if (logger.isDebugEnabled()) {
			logger.debug("json1bytes: " + json1String);
			logger.debug("json2bytes: " + json2String);
			logger.debug("fpmlbytes: " + fpmlString);			
		}
		try {
			marginCalculator.getValue(json1String, json2String, fpmlString);
		} catch (Exception e) {
			logger.error("Failed to calculate margin.");
			e.printStackTrace();
		}
		
		String resultJSON = marginCalculator.getContractValuationAsJSON();
		logger.info(resultJSON);
			try {
				Files.write( currentFile.toPath(), json1String.getBytes());
			} catch (IOException e) {
				throw new RuntimeException(e);
			}
			return new ResponseEntity<String>(resultJSON, responseHeaders, HttpStatus.OK);
	}
	
	/**
	 * Request mapping for the settlementvaluationForProductAsFPML
	 * 
	 * @param tradeAsFPML Trade FPML file
	 * @param marketDataAsJson1 Market data Json file1
	 * @param marketDataAsJson2 Market data Json file2
	 * @return String Json representing the valuation.
	 */
	public ResponseEntity<String> settlementvaluationForProductAsFPML(MultipartFile marketDataAsJson1, MultipartFile marketDataAsJson2, MultipartFile tradeAsFPML)
		{
		String json1String = null;
		try {
			json1String = new String(marketDataAsJson1.getBytes());
		} catch (IOException e) {
			throw new RuntimeException(e);
		}
		String json2String = null;
		try {
			json2String = new String(marketDataAsJson2.getBytes());
		} catch (IOException e) {
			throw new RuntimeException(e);
		}
		String fpmlString = null;
		try {
			fpmlString = new String(tradeAsFPML.getBytes());
		} catch (IOException e) {
			throw new RuntimeException(e);
		}

		LocalDate ld1 = SDCDateUtil.getDateFromJSON(json1String, SDCConstants.DATE_FORMAT_yyyyMMdd);
		LocalDate ld2 = SDCDateUtil.getDateFromJSON(json2String, SDCConstants.DATE_FORMAT_yyyyMMdd);

		HttpHeaders responseHeaders = new HttpHeaders();
		responseHeaders.add("Responded", "SettlementValuationControllerTwoCurves");
		boolean b = true;
		if (SDCProperties.getProperty(SDCConstants.MARKET_DATA_FILE_HEADER).equals("TRUE")) {
			b = SDCDateUtil.isFollowingBusinessDays(ld1, ld2, new BusinessdayCalendarExcludingTARGETHolidays());
		}
		
		if(!b) {
			String message = "The dates " + ld1 + " and  " + ld2 + " are not T, T-1 following business dates!";
			logger.error(message);
			return new ResponseEntity<String>(message, responseHeaders, HttpStatus.BAD_REQUEST);
		}
		logger.info("Starting Margin Calculation with dates " + ld1 + " and  " + ld2);
		MarginCalculator marginCalculator = new MarginCalculator();


		try {
			marginCalculator.getValue(json1String, json2String, fpmlString);
		} catch (Exception e) {
			logger.error("Failed to calculate margin.");
			e.printStackTrace();
		}
		if (logger.isDebugEnabled()) {
			logger.debug("json1bytes: " + json1String);
			logger.debug("json2bytes: " + json2String);
			logger.debug("fpmlbytes: " + fpmlString);
		}
		String resultJSON = marginCalculator.getContractValuationAsJSON();
		logger.info(resultJSON);
		return new ResponseEntity<String>(resultJSON, responseHeaders, HttpStatus.OK);
	}

	/**
	 * Request mapping for lastmargincalculationfpml
	 * 
	 * @param tradeId Trade ID
	 * @return String representing trade as fpml.
	 */
	public ResponseEntity<String> settlementvaluationProductAsFPML(String tradeId)
		{
		HttpHeaders responseHeaders = new HttpHeaders();
		responseHeaders.setContentType(MediaType.APPLICATION_JSON);
		responseHeaders.add("Responded", "lastmargincalculationfpml");
		String totalResult =  fpml.get(tradeId);
				
		return new ResponseEntity<String>(totalResult, responseHeaders, HttpStatus.OK);
	}

	/**
	 * Request mapping for test
	 * 
	 * @return String "Connect successful".
	 */
	public ResponseEntity<String> test()
		{
				
		HttpHeaders responseHeaders = new HttpHeaders();
		responseHeaders.setContentType(MediaType.APPLICATION_JSON);
		responseHeaders.add("Responded", "test");
		String totalResult =  "Connect successful";
				
		return new ResponseEntity<String>(totalResult, responseHeaders, HttpStatus.OK);
	}
}
