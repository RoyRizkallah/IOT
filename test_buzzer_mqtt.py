"""Send buzzer trigger directly to Pi MQTT broker and watch for the response."""
import json, time
import paho.mqtt.client as mqtt

BROKER = '192.168.137.38'
PORT = 1883
CONTROL_TOPIC = 'iot/pi/control'
TELEMETRY_TOPIC = 'iot/pi/telemetry'

received = []

def on_connect(c, userdata, flags, rc, props=None):
    print(f"Connected to Pi broker (rc={rc})")
    c.subscribe(TELEMETRY_TOPIC)
    print(f"Subscribed to {TELEMETRY_TOPIC}")

def on_message(c, userdata, msg):
    data = json.loads(msg.payload)
    received.append(data)
    buzzer = data.get('buzzer', 'N/A')
    temp   = data.get('temperature', 'N/A')
    print(f"  Telemetry → temp={temp}°C  buzzer={buzzer}")

try:
    client = mqtt.Client(callback_api_version=mqtt.CallbackAPIVersion.VERSION2)
except AttributeError:
    client = mqtt.Client()

client.on_connect = on_connect
client.on_message = on_message
client.connect(BROKER, PORT, 60)
client.loop_start()

time.sleep(2)

print("\n>>> Sending {buzzer: true} to Pi...")
client.publish(CONTROL_TOPIC, json.dumps({'buzzer': True}))
print("Command sent! Waiting 6s for telemetry response...\n")

time.sleep(6)

client.loop_stop()
client.disconnect()

if received:
    print(f"\nReceived {len(received)} telemetry message(s) — Pi publisher is alive and responding.")
else:
    print("\nNo telemetry received — publisher may not be connected to broker.")
