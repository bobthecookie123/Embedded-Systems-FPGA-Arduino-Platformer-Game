#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

// === Trail Logic ===
const int trailSize = 16;
const int trailMoveDelay = 8;
const int trailSpawnDelay = 100;

struct TrailDot {
  int x;
  int y;
};

TrailDot trail[trailSize];
unsigned long lastTrailMoveTime = 0;
unsigned long lastTrailSpawnTime = 0;
int nextTrailSlot = 0;

// === FSM and Movement ===
volatile bool pulseReceived = false;
int screenState = 1;
int lastScreenState = 0;
bool screenNeedsUpdate = true;

unsigned long lastPulseUpdate = 0;
int pulseStage = 0;

const int pulseInputPin  = 15;
const int tickPlayerYPin = 14;

unsigned long bootTime         = 0;
unsigned long lastJumpTime     = 0;

int playerY = 0;
bool isClimbing = false;
int playerYDisplay = 0;  // <=== Shared playerY display value for sync

// === Level Timer ===
unsigned long screen2StartTime = 0;
bool levelComplete = false;

// === Obstacle Blocks ===
const int MAX_BLOCKS = 16;
int blockX[MAX_BLOCKS];
int blockLane[MAX_BLOCKS];
int blockCount = 0;

const int blockSpeedDelay = 31;
unsigned long lastBlockMoveTime = 0;

// === Per-lane debounce ===
unsigned long lastLanePulseTime[4] = {0, 0, 0, 0};
const unsigned long laneDebounceTime = 10; // ms between pulses per lane

// === Y offset to match FPGA ===
const int Y_VISUAL_OFFSET = 1;

// === ISR: Spawn Blocks on GPIO Pulse ===
void spawnBlock(int lane) {
  unsigned long now = millis();
  if (blockCount >= MAX_BLOCKS) return;
  if (now - lastLanePulseTime[lane] < laneDebounceTime) return;

  lastLanePulseTime[lane] = now;
  blockX[blockCount] = 128;
  blockLane[blockCount] = lane;
  blockCount++;
  screenNeedsUpdate = true;
}

void onLane1() { spawnBlock(0); }
void onLane2() { spawnBlock(1); }
void onLane3() { spawnBlock(2); }
void onLane4() { spawnBlock(3); }
void onPulseReceived() { pulseReceived = true; }

void setup() {
  Serial.begin(9600);
  while (!Serial) delay(10);

  Wire.setSDA(0);
  Wire.setSCL(1);
  Wire.begin();

  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println("OLED init failed!");
    while (1);
  }

  display.clearDisplay();
  display.display();

  pinMode(pulseInputPin, INPUT);
  pinMode(tickPlayerYPin, INPUT);
  attachInterrupt(digitalPinToInterrupt(pulseInputPin), onPulseReceived, RISING);

  for (int pin = 6; pin <= 9; pin++) {
    pinMode(pin, INPUT); // Pulldowns handled externally
  }

  attachInterrupt(digitalPinToInterrupt(6), onLane1, RISING);
  attachInterrupt(digitalPinToInterrupt(7), onLane2, RISING);
  attachInterrupt(digitalPinToInterrupt(8), onLane3, RISING);
  attachInterrupt(digitalPinToInterrupt(9), onLane4, RISING);

  bootTime = millis();

  for (int i = 0; i < trailSize; i++) {
    trail[i].x = -4;
    trail[i].y = 0;
  }
}

void loop() {
  unsigned long currentTime = millis();

  // === FSM Pulse ===
  if (pulseReceived && currentTime - bootTime > 1000) {
    pulseReceived = false;
    screenState++;
    if (screenState > 3) screenState = 1;
    screenNeedsUpdate = true;

    if (screenState == 2) {
      screen2StartTime = millis();
      levelComplete = false;
      blockCount = 0;
    }

    if (screenState == 3) {
      levelComplete = false;
      screen2StartTime = 0;
    }
  }

  // === Idle Animation ===
  if (screenState == 1 && currentTime - lastPulseUpdate > 400) {
    pulseStage = (pulseStage + 1) % 4;
    lastPulseUpdate = currentTime;
    screenNeedsUpdate = true;
  }

  // === Player Movement ===
  bool climbSignal = digitalRead(tickPlayerYPin) == HIGH;
  if (screenState == 2 && currentTime - lastJumpTime >= 31 && !levelComplete) {
    if (climbSignal && playerY < 64) playerY++;
    else if (!climbSignal && playerY > 0) playerY--;
    isClimbing = climbSignal;
    lastJumpTime = currentTime;
    screenNeedsUpdate = true;
  }

  // === Trail Movement ===
  if (screenState == 2 && currentTime - lastTrailMoveTime >= trailMoveDelay && !levelComplete) {
    for (int i = 0; i < trailSize; i++) {
      if (trail[i].x > -2) trail[i].x -= 1;
    }
    lastTrailMoveTime = currentTime;
    screenNeedsUpdate = true;
  }

  // === Trail Spawning ===
  if (screenState == 2 && currentTime - lastTrailSpawnTime >= trailSpawnDelay && !levelComplete) {
    trail[nextTrailSlot].x = 30;
    trail[nextTrailSlot].y = playerYDisplay; // <=== Now synced with actual player drawing
    nextTrailSlot = (nextTrailSlot + 1) % trailSize;
    lastTrailSpawnTime = currentTime;
    screenNeedsUpdate = true;
  }

  // === Obstacle Movement ===
  if (screenState == 2 && currentTime - lastBlockMoveTime >= blockSpeedDelay && !levelComplete) {
    for (int i = 0; i < blockCount; i++) {
      blockX[i] -= 1;
    }

    int writeIndex = 0;
    for (int i = 0; i < blockCount; i++) {
      if (blockX[i] > -32) {
        blockX[writeIndex] = blockX[i];
        blockLane[writeIndex] = blockLane[i];
        writeIndex++;
      }
    }
    blockCount = writeIndex;

    lastBlockMoveTime = currentTime;
    screenNeedsUpdate = true;
  }

  // === Level Completion ===
  if (screenState == 2 && !levelComplete && currentTime - screen2StartTime >= 20000) {
    levelComplete = true;
    screenNeedsUpdate = true;
    Serial.println("Level Complete");
  }

  // === Display Refresh ===
  if (screenState != lastScreenState || screenNeedsUpdate) {
    display.clearDisplay();

    switch (screenState) {
      case 1: drawIdleScreen(); break;
      case 2: drawGameScreen(); break;
      case 3: drawGameOverScreen(); break;
    }

    display.display();
    lastScreenState = screenState;
    screenNeedsUpdate = false;
  }
}

void drawIdleScreen() {
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0);
  display.print("Game Starting");
  for (int i = 0; i < pulseStage; i++) display.print(".");
  display.setCursor(0, 16);
  display.println("Press KEY[1] to begin");
}

void drawGameScreen() {
  int ypos = SCREEN_HEIGHT - playerY - Y_VISUAL_OFFSET;
  playerYDisplay = ypos; // <=== Set display y-position here
  int xpos = 32;

  if (!levelComplete) {
    for (int i = 0; i < trailSize; i++) {
      if (trail[i].x > -2 && trail[i].x < SCREEN_WIDTH) {
        display.drawPixel(trail[i].x, trail[i].y, WHITE);
      }
    }

    if (isClimbing) {
      display.drawTriangle(xpos - 2, ypos + 6, xpos - 6, ypos - 6, xpos + 10, ypos - 6, WHITE);
    } else {
      display.drawTriangle(xpos - 6, ypos + 6, xpos - 2, ypos - 6, xpos + 10, ypos + 6, WHITE);
    }

    display.drawCircle(xpos - 2, ypos, 3, WHITE);

    for (int i = 0; i < blockCount; i++) {
      int x = blockX[i];
      int y = blockLane[i] * 16;
      display.drawRect(x, y, 32, 16, WHITE); // outline only
    }
  }

  if (levelComplete) {
    display.setTextSize(2);
    display.setTextColor(SSD1306_WHITE);
    display.setCursor(16, 16);
    display.println("Level");
    display.setCursor(21, 34);
    display.println("Complete");
  }
}

void drawGameOverScreen() {
  display.setTextSize(2);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(10, 25);
  display.println("Game Over");
}
