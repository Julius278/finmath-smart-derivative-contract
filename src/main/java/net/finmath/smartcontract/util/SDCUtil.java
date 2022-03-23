/*
 * 
 *
 * @author Dietmar Schnabel
 */
package net.finmath.smartcontract.util;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

/**
 * The Class SDCUtil.
 */
public class SDCUtil {
	
	/**
	 * Checks if is empty.
	 *
	 * @param string the string
	 * @return true, if is empty
	 */
	public static boolean isEmpty(String string) {
		if (string == null || string.equals("")) {
			return true;
		}
		return false;
	}
	
	/**
	 * Gets a field from Contract Valuation JSON file .
	 *
	 * @param json the json
	 * @param key string
	 * @return the field from JSON
	 */
	public static String getFieldFromJSON (String json, String key) {
		JsonParser parser = new JsonParser();
		JsonElement element = parser.parse(json); 
		JsonObject jsonObject = element.getAsJsonObject();
		String value = jsonObject.get(key).getAsString();
			
		return value;
	}
}