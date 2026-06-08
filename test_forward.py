"""Test MQTT through the forwarded address 172.16.128.41:1883"""
import json, time
import paho.mqtt.client as mqtt

received = []

def on_connect(c, u, f, rc, p=None):
    print(f"Connected via forwarded address (rc={rc})")
    c.subscribe('iot/pi/telemetry')

def on_message(c, u, msg):
    data = json.loads(msg.payload)
    received.append(data)
    print(f"  Pi telemetry received: temp={data.get('temperature')} buzzer={data.get('buzzer')}")

try:
    client = mqtt.Client(callback_api_version=mqtt.CallbackAPIVersion.VERSION2)
except AttributeError:
    client = mqtt.Client()

client.on_connect = on_connect
client.on_message = on_message

print("Connecting to 172.16.128.41:1883 (PC forward -> Pi)...")
try:
    client.connect('172.16.128.41', 1883, 60)
except Exception as e:
    print(f"FAILED to connect: {e}")
    exit(1)

client.loop_start()
time.sleep(2)

print("Sending buzzer trigger...")
client.publish('iot/pi/control', json.dumps({'buzzer': True}))
time.sleep(6)

client.loop_stop()
client.disconnect()

if received:
    print(f"\nSUCCESS: Received {len(received)} telemetry messages through forwarded address.")
else:
    print("\nFAIL: No telemetry received — forwarding not working.")
