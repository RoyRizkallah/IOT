import paramiko

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.137.38', username='pi', password='qwerty123', timeout=15)

def run(cmd):
    _, stdout, stderr = client.exec_command(cmd, timeout=20)
    return (stdout.read() + stderr.read()).decode('utf-8', errors='replace').strip()

print("=== pi_sensor_publisher.py ===")
print(run("cat ~/iot-demo/pi_sensor_publisher.py"))

client.close()
