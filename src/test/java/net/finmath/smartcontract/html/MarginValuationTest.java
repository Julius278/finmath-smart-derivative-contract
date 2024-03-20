package net.finmath.smartcontract.html;

import com.microsoft.playwright.*;
import org.junit.jupiter.api.*;

import java.nio.file.Paths;

import static com.microsoft.playwright.assertions.PlaywrightAssertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertTrue;

/*@ExtendWith(SpringExtension.class)
@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.DEFINED_PORT,
        properties = {"server.port=8042"},
        classes = {Application.class, BasicAuthWebSecurityConfiguration.class}
)*/
//@WebMvcTest(Application.class)
//@AutoConfigureMockMvc(addFilters = false)
class MarginValuationTest {
    private int port = 8080;

    private static final Playwright playwright = Playwright.create();
    private Page page;
    private Browser browser;

    @BeforeEach
    void setUp() throws InterruptedException {
        // Define username and password credentials for authentication
        String username = "user1";
        String password = "password1";

        // Launch a Chromium browser in non-headless mode
        //browser = playwright.chromium().launch(new BrowserType.LaunchOptions().setHeadless(false));
        browser = playwright.chromium().launch(new BrowserType.LaunchOptions().setHeadless(true));

        // Create a Browser Context with HTTP credentials
        BrowserContext context = browser.newContext(new Browser.NewContextOptions().setHttpCredentials(username, password));
        //context = browser.newContext();

        // Create a new Page within the Browser Context
        page = context.newPage();
        // Navigate to the protected URL requiring authentication
        page.navigate("http://localhost:" + port + "/");

        // Introduce a delay to observe the authentication popup handling
        Thread.sleep(3_000);
    }

    @Test
    void testCheck() {
        page.navigate("http://localhost:" + port + "/");
        assertThat(page.getByText("Go").first()).isVisible();
    }

    @Test
    void calculateMargin() throws InterruptedException {
        page.navigate("http://localhost:" + port + "/margin-valuation.html");

        //insert fpml xml
        Locator b1 = page.getByLabel("Product Data File").first();
        assertThat(b1).isVisible();
        FileChooser fileChooser = page.waitForFileChooser(b1::click);
        fileChooser.setFiles(Paths.get("./src/main/resources/net.finmath.smartcontract.product.xml/smartderivativecontract.xml"));

        //insert marketData start xml
        Locator b2 = page.getByLabel("Market Data Start File").first();
        assertThat(b2).isVisible();
        fileChooser = page.waitForFileChooser(b2::click);
        fileChooser.setFiles(Paths.get("./src/main/resources/net/finmath/smartcontract/valuation/client/md_testset1.xml"));

        //insert marketData end xml
        Locator b3 = page.getByLabel("Market Data End File").first();
        assertThat(b3).isVisible();
        fileChooser = page.waitForFileChooser(b3::click);
        fileChooser.setFiles(Paths.get("./src/main/resources/net/finmath/smartcontract/valuation/client/md_testset2.xml"));

        //click calculate button
        Locator b4 = page.getByText("calculate").first();
        assertThat(b4).isVisible();
        b4.click();

        //wait for margin request to calculate
        Thread.sleep(10000);

        Locator b5 = page.getByLabel("valuationResult").first();
        System.out.println("Result: " + b5.textContent());
        assertThat(b5).isVisible();
        assertTrue(b5.textContent().contains("Valuation Result"));
        assertTrue(b5.textContent().contains("9908.52"));
    }

    @AfterEach
    void cleanUp() {
        browser.close();
    }

    @AfterAll
    static void cleanUpEnd() {
        playwright.close();
    }
}
