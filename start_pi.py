import paramiko, time

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.137.38', username='pi', password='qwerty123', timeout=15)

def run(cmd, timeout=20):
    _, stdout, stderr = client.exec_command(cmd, timeout=timeout)
    return (stdout.read() + stderr.read()).decode('utf-8', errors='replace').strip()

# Kill any stale instances first
run("pkill -f pi_sensor_publisher.py 2>/dev/null; pkill -f pi_camera_streamer.py 2>/dev/null")
time.sleep(1)

# Start sensor publisher in background
run("nohup bash -c 'cd ~/iot-demo && source venv/bin/activate 2>/dev/null; python pi_sensor_publisher.py > /tmp/publisher.log 2>&1 &' &")
time.sleep(2)

# Start camera streamer in background
run("nohup bash -c 'cd ~/iot-demo && source venv/bin/activate 2>/dev/null; python pi_camera_streamer.py > /tmp/camera.log 2>&1 &' &")
time.sleep(2)

# Verify both are running
print("=== Running processes ===")
print(run("pgrep -a -f 'pi_sensor_publisher|pi_camera_streamer'"))

print("\n=== Publisher log (last 8 lines) ===")
print(run("tail -8 /tmp/publisher.log 2>/dev/null || echo 'no log yet'"))

print("\n=== Camera log (last 5 lines) ===")
print(run("tail -5 /tmp/camera.log 2>/dev/null || echo 'no log yet'"))

client.close()
