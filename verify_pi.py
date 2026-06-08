import paramiko

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.137.38', username='pi', password='qwerty123', timeout=15)

def run(cmd, timeout=20):
    _, stdout, stderr = client.exec_command(cmd, timeout=timeout)
    return (stdout.read() + stderr.read()).decode('utf-8', errors='replace').strip()

print("=== 1. MQTT Broker (Mosquitto) ===")
print(run("systemctl is-active mosquitto 2>/dev/null || echo 'not a service'"))
print(run("pgrep -a mosquitto 2>/dev/null || echo 'mosquitto NOT running'"))

print("\n=== 2. Sensor Publisher ===")
print(run("pgrep -a -f pi_sensor_publisher 2>/dev/null || echo 'publisher NOT running'"))

print("\n=== 3. Camera Streamer ===")
print(run("pgrep -a -f pi_camera_streamer 2>/dev/null || echo 'camera streamer NOT running'"))

print("\n=== 4. GPIO 17 (Buzzer pin) accessible ===")
print(run("ls /sys/class/gpio/ 2>/dev/null | head -5"))

print("\n=== 5. Buzzer code in publisher ===")
print(run("grep -n 'BUZZER_PIN\\|buzzer_hw\\|Manual trigger\\|TEMP_BUZZER' ~/iot-demo/pi_sensor_publisher.py | head -8"))

print("\n=== 6. Network (Pi IP) ===")
print(run("hostname -I"))

client.close()
