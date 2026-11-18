#include <ESP8266WiFi.h>
#include <ESP8266HTTPClient.h>
#include <WiFiClientSecure.h>

// WiFi Credentials
const char* ssid = "ALISSON";
const char* password = "#91004569#";

// Discord Webhook URL
const char* webhookUrl = "https://discord.com/api/webhooks/1228500829879668736/mqulP0SmfzQ2jicxTiuz-7__aCKkkomt8mi6sbT4SBqhxZzH2c5krxSVC6J-FB1jQlKT";

// Relay Pin Definitions (using GPIO numbers)
const int WATER_INLET_PIN = 12;   // GPIO5 (D1) // Swapped with green lamp
const int MOTOR_PIN = 4;         // GPIO4 (D2) -> THIS WORKS
const int DRAIN_PIN = 0;         // GPIO0 (D3, optional for future use)
const int DRAIN_LIGHT_PIN = 2;   // GPIO2 (D4, BLUE for drain action needed)
const int CYCLE_COMPLETE_LIGHT_PIN = 5; // GPIO12 (D6, GREEN Light for cycle complete) // swapped with inlet -> THIS WORKS

// Manual Drain Control Pins
const int DRAIN_BUTTON_PIN = 14; // GPIO14 (D5, confirmation button)

void setup() {
  Serial.begin(115200);
  delay(100);
  
  // Initialize relay pins as outputs (relays off = HIGH for active-low relays)
  pinMode(WATER_INLET_PIN, OUTPUT);
  pinMode(MOTOR_PIN, OUTPUT);
  pinMode(DRAIN_PIN, OUTPUT);
  pinMode(DRAIN_LIGHT_PIN, OUTPUT);
  pinMode(CYCLE_COMPLETE_LIGHT_PIN, OUTPUT);
  
  // Initialize manual drain control pins
  pinMode(DRAIN_BUTTON_PIN, INPUT_PULLUP); // Button with internal pull-up resistor
  
  // Turn off all relays initially (HIGH = off for most relay modules)
  digitalWrite(WATER_INLET_PIN, HIGH);
  digitalWrite(MOTOR_PIN, HIGH);
  digitalWrite(DRAIN_PIN, HIGH);
  digitalWrite(DRAIN_LIGHT_PIN, HIGH);
  digitalWrite(CYCLE_COMPLETE_LIGHT_PIN, HIGH);
  
  Serial.println("\n\nWashing Machine Controller Starting...");
  

  // Run self-check test on all relays
  runSelfCheck();


  // Connect to WiFi
  connectWiFi();


  
  Serial.println("System ready! Starting wash cycle automatically...");
  
  // Start the washing cycle automatically
  runWashCycle();
}

void loop() {
  // After cycle completes, wait for button press to start new cycle
  // Check if cycle complete light is on (indicates cycle finished)
  if (digitalRead(CYCLE_COMPLETE_LIGHT_PIN) == LOW) {
    Serial.println("Waiting for button press to start new cycle...");
    waitForButtonPress();
    
    // Turn off cycle complete light
    digitalWrite(CYCLE_COMPLETE_LIGHT_PIN, HIGH);
    
    // Make sure all relays are off before starting new cycle
    digitalWrite(WATER_INLET_PIN, HIGH);
    digitalWrite(MOTOR_PIN, HIGH);
    digitalWrite(DRAIN_PIN, HIGH);
    digitalWrite(DRAIN_LIGHT_PIN, HIGH);
    
    Serial.println("Button pressed! Starting new wash cycle...");
    delay(500);
    
    // Start new washing cycle
    runWashCycle();
  }
  
  delay(1000);
}

void connectWiFi() {
  Serial.print("Connecting to WiFi: ");
  Serial.println(ssid);
  
  WiFi.begin(ssid, password);
  
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 30) {
    delay(500);
    Serial.print(".");
    attempts++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nWiFi Connected!");
    Serial.print("IP Address: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("\nWiFi Connection Failed!");
  }
}

void runSelfCheck() {
  Serial.println("\n========== RUNNING SELF-CHECK TEST ==========");
  Serial.println("Testing all relays (500ms each)...");
  
  // Array of all relay pins and their names
  int relayPins[] = {
    WATER_INLET_PIN, // We will use this
    MOTOR_PIN, // We will use this
    DRAIN_PIN,
    DRAIN_LIGHT_PIN,
    CYCLE_COMPLETE_LIGHT_PIN
  };
  
  const char* relayNames[] = {
    "Water Inlet",
    "Motor",
    "Drain",
    "Drain Light (Blue)",
    "Cycle Complete Light (Green)"
  };
  
  int numRelays = sizeof(relayPins) / sizeof(relayPins[0]);
  
  // Test each relay sequentially
  for (int i = 0; i < numRelays; i++) {
    Serial.printf("Testing %s (GPIO %d)...\n", relayNames[i], relayPins[i]);
    
    // Turn ON relay (LOW = on for active-low relays)
    digitalWrite(relayPins[i], LOW);
    delay(1000); // 500ms ON
    
    // Turn OFF relay (HIGH = off)
    digitalWrite(relayPins[i], HIGH);
    delay(200); // Small delay between tests
    
    Serial.printf("  %s test complete!\n", relayNames[i]);
  }
  
  Serial.println("========== SELF-CHECK TEST COMPLETE ==========\n");
}

void sendDiscordMessage(String message) {
  // Skip if WiFi not connected - work without internet
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi not connected, skipping Discord message");
    Serial.printf("Message would be: %s\n", message.c_str());
    return;
  }
  
  WiFiClientSecure client;
  client.setInsecure(); // For simplicity, skip certificate validation
  
  HTTPClient http;
  
  if (http.begin(client, webhookUrl)) {
    http.addHeader("Content-Type", "application/json");
    http.setTimeout(5000); // 5 second timeout
    
    // Create JSON payload
    String payload = "{\"content\":\"" + message + "\"}";
    
    int httpCode = http.POST(payload);
    
    if (httpCode > 0) {
      Serial.printf("Discord message sent, response: %d\n", httpCode);
    } else {
      Serial.printf("Discord message failed: %s (continuing anyway)\n", http.errorToString(httpCode).c_str());
    }
    
    http.end();
  } else {
    Serial.println("Failed to connect to Discord webhook (continuing anyway)");
  }
  
  delay(100); // Small delay to avoid rate limiting
}

void fillWater(int totalMinutes) {
  Serial.printf("Starting water fill for %d minutes total...\n", totalMinutes);
  
  int totalSeconds = totalMinutes * 60;
  int cycles = totalSeconds / 60; // Each cycle is 30s on + 30s off = 60s total
  int remainingSeconds = totalSeconds % 60;
  
  Serial.printf("Running %d cycles of 30s on/30s off\n", cycles);
  
  // Run cycles: 30s on, 30s off
  for (int i = 0; i < cycles; i++) {
    Serial.printf("Water fill cycle %d/%d - 30 seconds ON\n", i + 1, cycles);
    digitalWrite(WATER_INLET_PIN, LOW); // Turn ON
    delay(30000); // 30 seconds
    
    Serial.printf("Water fill cycle %d/%d - 30 seconds OFF\n", i + 1, cycles);
    digitalWrite(WATER_INLET_PIN, HIGH); // Turn OFF
    delay(30000); // 30 seconds
  }
  
  // Handle remaining seconds if any (less than 60 seconds)
  if (remainingSeconds > 0) {
    if (remainingSeconds <= 30) {
      // If 30 seconds or less, just run for that time
      Serial.printf("Final water fill for %d seconds\n", remainingSeconds);
      digitalWrite(WATER_INLET_PIN, LOW); // Turn ON
      delay(remainingSeconds * 1000);
      digitalWrite(WATER_INLET_PIN, HIGH); // Turn OFF
    } else {
      // If more than 30 seconds, run 30s on, then wait the rest
      Serial.println("Final water fill - 30 seconds ON");
      digitalWrite(WATER_INLET_PIN, LOW); // Turn ON
      delay(30000); // 30 seconds
      digitalWrite(WATER_INLET_PIN, HIGH); // Turn OFF
      delay((remainingSeconds - 30) * 1000); // Wait remaining time
    }
  }
  
  Serial.println("Water fill complete!");
}

void waitMinutes(int minutes) {
  Serial.printf("Waiting for %d minutes (soak cycle)...\n", minutes);
  
  // Break into smaller chunks for better monitoring
  for (int i = 0; i < minutes; i++) {
    delay(60000); // 1 minute
    Serial.printf("Soak time remaining: %d minutes\n", minutes - i - 1);
  }
  
  Serial.println("Wait period complete!");
}

void runMotor(int minutes) {
  Serial.printf("Running motor for %d minutes...\n", minutes);
  
  // Turn motor ON
  digitalWrite(MOTOR_PIN, LOW);
  
  // Run for specified time
  delay(minutes * 60000);
  
  // Turn motor OFF
  digitalWrite(MOTOR_PIN, HIGH);
  
  Serial.println("Motor cycle complete!");
}

void waitForButtonPress() {
  // Wait for button state change (edge detection)
  // Read initial state
  int lastButtonState = digitalRead(DRAIN_BUTTON_PIN);
  int currentButtonState;
  bool buttonPressed = false;
  
  Serial.println("Waiting for button press (state change)...");
  
  while (!buttonPressed) {
    currentButtonState = digitalRead(DRAIN_BUTTON_PIN);
    
    // Detect state change (either HIGH to LOW or LOW to HIGH)
    if (currentButtonState != lastButtonState) {
      delay(50); // Debounce delay
      currentButtonState = digitalRead(DRAIN_BUTTON_PIN);
      
      // Verify the state change is still present after debounce
      if (currentButtonState != lastButtonState) {
        buttonPressed = true;
        Serial.printf("Button state changed from %d to %d\n", lastButtonState, currentButtonState);
      }
    }
    
    lastButtonState = currentButtonState;
    delay(10); // Small delay to avoid excessive CPU usage
  }
  
  delay(200); // Additional delay after button press
}

void waitForManualDrain() {
  Serial.println("\n========== MANUAL DRAIN REQUIRED ==========");
  
  // Step 1: Open the drain valve
  Serial.println("Step 1: Waiting for drain valve to be opened...");
  

  // Turn on drain light to indicate action needed
  digitalWrite(DRAIN_LIGHT_PIN, LOW); // LOW = on for relay modules
  Serial.println("Drain light turned ON - waiting for button press...");
  
  // Wait for button press
  waitForButtonPress();
  
  // Turn off drain light
  digitalWrite(DRAIN_LIGHT_PIN, HIGH);
  Serial.println("Button pressed! Drain light turned OFF. Valve open confirmed.");
  sendDiscordMessage("✅ Drain valve opened! Waiting 15 minutes for water to drain...");
  
  // Step 2: Wait for water to drain (15 minutes)
  Serial.println("Waiting 15 minutes for water to drain...");
  delay(900000); // 15 minutes = 900,000 milliseconds
  
  Serial.println("Drain time complete!");
  sendDiscordMessage("🧺 **Close Drain valve then press the button**");
  
  // Step 3: Close the drain valve
  Serial.println("Step 2: Waiting for drain valve to be closed...");
  
  // Turn on drain light again
  digitalWrite(DRAIN_LIGHT_PIN, LOW);
  Serial.println("Drain light turned ON - waiting for button press...");
  
  // Wait for button press
  waitForButtonPress();
  
  // Turn off drain light
  digitalWrite(DRAIN_LIGHT_PIN, HIGH);
  Serial.println("Button pressed! Drain light turned OFF. Valve closed confirmed.");
  
  // Send confirmation to Discord
  sendDiscordMessage("✅ Drain valve closed! Continuing wash cycle...");
  
  delay(500); // Small delay before continuing
}

void runWashCycle() {
  Serial.println("\n========== STARTING WASH CYCLE ==========\n");
  sendDiscordMessage("🧺 **Washing Machine Cycle Started!**");
  
  // FILL 1 - 15 minutes (30s on/30s off cycles)
  fillWater(15);
  waitMinutes(1);

  // WASH 1  
  runMotor(15);
  waitMinutes(1);
  sendDiscordMessage("🧺 **Open Drain valve then press the button**");
  waitForManualDrain();
  
  // FILL 2 - 15 minutes (30s on/30s off cycles)
  fillWater(15);
  waitMinutes(10);

  // WASH 2
  runMotor(7);
  waitMinutes(1);
  sendDiscordMessage("🧺 **Open Drain valve then press the button**");
  waitForManualDrain();
  
  sendDiscordMessage("🎉 **Washing cycle complete! Time to get your clothes!** 👕👖");
  
  // Turn on cycle complete light
  digitalWrite(CYCLE_COMPLETE_LIGHT_PIN, LOW); // LOW = on for relay modules
  Serial.println("Cycle complete light turned ON!");
  
  // Make sure all other relays are off
  digitalWrite(WATER_INLET_PIN, HIGH);
  digitalWrite(MOTOR_PIN, HIGH);
  digitalWrite(DRAIN_PIN, HIGH);
  digitalWrite(DRAIN_LIGHT_PIN, HIGH);
}