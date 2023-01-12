package net.finmath.smartcontract.marketdata.adapters;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.neovisionaries.ws.client.WebSocket;
import com.neovisionaries.ws.client.WebSocketAdapter;
import net.finmath.smartcontract.marketdata.util.IRMarketDataItem;
import net.finmath.smartcontract.marketdata.util.IRMarketDataParser;


import java.util.*;
import java.util.concurrent.Callable;
import java.util.stream.Collectors;

public class CallableRetrieveMarketdata extends WebSocketAdapter implements Callable<String> {

    private final JsonNode authJson;
    private final String position;
    private final Map<String, IRMarketDataItem> marketdataItemMap;

    boolean requestSent;

    public CallableRetrieveMarketdata(JsonNode authJson, String position, List<IRMarketDataItem> itemList) {
        this.authJson = authJson;
        this.position = position;
        this.marketdataItemMap = itemList.stream().collect(Collectors.toMap(r->r.getRic(),r->r));
        requestSent = false;
    }


    public Set<IRMarketDataItem>     getMarketDataItems(){
        return marketdataItemMap.values().stream().collect(Collectors.toSet());
    }

    /**
     * Called when handshake is complete and websocket is open, send login
     */
    public void onConnected(WebSocket websocket, Map<String, List<String>> headers) throws Exception {
        System.out.println("WebSocket successfully connected!");
        sendLoginRequest(websocket, authJson.get("access_token").asText(), true);

    }

    public void onTextMessage(WebSocket websocket, String message) throws Exception {
        if (!message.isEmpty()) {

            ObjectMapper mapper = new ObjectMapper();
            JsonNode responseJson = mapper.readTree(message);

            if (!requestSent) {
                sendRICRequest(websocket);
                requestSent = true;
            }

            try {
                for (int i = 0; i < responseJson.size(); i++) {
                    if (responseJson.get(i).has("Fields")) {
                        String ric = responseJson.get(i).get("Key").get("Name").asText();
                        JsonNode fields = responseJson.get(i).get("Fields");
                        Double BID = fields.has("BID") ? fields.get("BID").doubleValue() : null;
                        Double ASK = fields.has("ASK") ? fields.get("ASK").doubleValue() : null;
                        Double quote = ASK == null ? BID : BID == null ? ASK : (BID + ASK) / 2.0 / 100.;
                        this.marketdataItemMap.get(ric).setValue(quote);
                        this.marketdataItemMap.get(ric).setDate(fields.get("VALUE_DT1").textValue()); //fields.getString("VALUE_DT1"), fields.getString("VALUE_TS1")
                        this.marketdataItemMap.get(ric).setTimestamp(fields.get("VALUE_TS1").textValue());
                    }

                }
            } catch (Exception e) {
                //  System.out.println("FAIL");
//                websocket.disconnect();
            }
        }

    }



    /**
     * Create and send simple Market Price request
     * @param websocket Websocket to send the message on
     * @throws Exception
     */
    public void sendRICRequest(WebSocket websocket) throws Exception {
        String requestJsonString;
        String keyString1 = ricsToString(); //;+ ",\"Service\":\""; // + this.refinitiv_service_key + "\"}}"; //
        requestJsonString = "{\"ID\":2,"+keyString1+",\"View\":[\"MID\",\"BID\",\"ASK\",\"VALUE_DT1\",\"VALUE_TS1\"]}";
        websocket.sendText(requestJsonString);
    }


    public void sendLoginRequest(WebSocket websocket, String authToken, boolean isFirstLogin) throws Exception {
        String loginJsonString = "{\"ID\":1,\"Domain\":\"Login\",\"Key\":{\"Elements\":{\"ApplicationId\":\"\",\"Position\":\"\",\"AuthenticationToken\":\"\"},\"NameType\":\"AuthnToken\"}}";
        ObjectMapper mapper = new ObjectMapper();

        ObjectNode loginJson = (ObjectNode) mapper.readTree(loginJsonString);
         ((ObjectNode) loginJson.get("Key").get("Elements")).put("AuthenticationToken",authToken);
        ((ObjectNode) loginJson.get("Key").get("Elements")).put("ApplicationId","256");
        ((ObjectNode) loginJson.get("Key").get("Elements")).put("Position",this.position);

        if (!isFirstLogin) { // If this isn't our first login, we don't need another refresh for it.
            ((ObjectNode) loginJson).put("Refresh", false);//.get("Key").get("Elements")).put("Position",this.position);
        }

        websocket.sendText(loginJson.toString());

    }


    private String      ricsToString(){

        String ricsAsString = "\"Key\":{\"Name\":[";

        for (IRMarketDataItem item : this.marketdataItemMap.values())
            ricsAsString = ricsAsString + "\"" + item.getRic() + "\",";
        ricsAsString = ricsAsString.substring(0,ricsAsString.length()-1);
        ricsAsString += "]}";

        return ricsAsString;


    }

    @Override
    public String call() throws Exception {
        while(true) {
            long quotesRetrieved = this.getMarketDataItems().stream().filter(item -> item.getValue() != null).count();
            if (quotesRetrieved == this.getMarketDataItems().size()) {
                String json = IRMarketDataParser.serializeToJson(this.getMarketDataItems());
                try {
                    this.getMarketDataItems().forEach(item -> {
                        item.setValue(null);
                    });
                    requestSent = false;
                    return json;
                } catch (Exception e) {
                    return "";
                }
            }

        }
    }


}