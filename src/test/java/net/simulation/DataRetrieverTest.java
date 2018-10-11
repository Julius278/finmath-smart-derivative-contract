package net.simulation;

import java.io.File;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.stream.Collectors;

import com.google.gson.Gson;
import net.finmath.smartcontract.simulation.scenariogeneration.IRCurveData;
import net.finmath.smartcontract.simulation.scenariogeneration.IRMarketDataScenario;
import org.junit.Assert;
import org.junit.Ignore;
import org.junit.Test;



public class DataRetrieverTest {


    DateTimeFormatter formatter = DateTimeFormatter.ofPattern("yyyyMMdd");
    @Ignore
    @Test
    public void testDataImport(){
        try {

            String content = new Scanner(new File("timeseriesdatamap.json")).next();
            Gson gson = new Gson();
            //Class aClass = new HashMap<String,Map<String,Map<String,Pair<String,Double>>>>().getClass();
            Map<String,Map<String,Map<String,Map<String,Double>>>>  timeSeriesDatamap = gson.fromJson(content,new HashMap<String,Map<String,Map<String,Map<String,Double>>>>().getClass());

            List<IRMarketDataScenario> scenarioSet = timeSeriesDatamap.entrySet().stream().map(scenarioData->{
                Map<String,IRCurveData> map = scenarioData.getValue().entrySet().stream().collect(Collectors.toMap(entry->entry.getKey(), entry->new IRCurveData(entry.getKey(),entry.getValue())));
                String dateTime = scenarioData.getKey();
                LocalDateTime time = LocalDate.parse(dateTime,formatter).atTime(17,0);
                IRMarketDataScenario scenario = new IRMarketDataScenario(map, time);
                return scenario;
            }).sorted((S1, S2) -> S1.getDate().compareTo(S2.getDate())).collect(Collectors.toList());



            Assert.assertNotNull(timeSeriesDatamap);

        }
        catch(Exception e){
            System.out.println(e);
        }
    }


}