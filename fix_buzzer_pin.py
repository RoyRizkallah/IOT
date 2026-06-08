import paramiko, io, time

c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect('192.168.137.38', username='pi', password='qwerty123', timeout=15)

def run(cmd, timeout=10):
    _, o, e = c.exec_command(cmd, timeout=timeout)
    return (o.read() + e.read()).decode('utf-8', 'replace').strip()

# Just update the pin number
sftp = c.open_sftp()
with sftp.open('/home/pi/iot-demo/pi_sensor_publisher.py', 'r') as f:
    content = f.read().decode('utf-8')

updated = content.replace(
    'BUZZER_PIN       = 17   # Active buzzer on GPIO 17',
    'BUZZER_PIN       = 18   # Buzzer on GPIO 18 (pin 12)'
).replace(
    'BUZZER_PIN       = 17',
    'BUZZER_PIN       = 18'
)

sftp.putfo(io.BytesIO(updated.encode()), '/home/pi/iot-demo/pi_sensor_publisher.py')
sftp.close()
print("Pin updated to 18:", run("grep 'BUZZER_PIN' ~/iot-demo/pi_sensor_publisher.py | head -2"))

# Restart
run("pkill -f pi_sensor_publisher 2>/dev/null")
time.sleep(1)
run("nohup bash -c 'cd ~/iot-demo && python pi_sensor_publisher.py > /tmp/publisher.log 2>&1 &' &")
time.sleep(2)
print("Publisher running:", run("pgrep -c -f pi_sensor_publisher"))
c.close()
