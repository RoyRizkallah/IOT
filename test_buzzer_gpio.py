import paramiko, time, io

SCRIPT = b"""
import subprocess, time
import RPi.GPIO as GPIO

subprocess.run(['pkill', '-f', 'pi_sensor_publisher'], capture_output=True)
time.sleep(1)

GPIO.setmode(GPIO.BCM)
GPIO.setup(18, GPIO.OUT)

# Try PWM (passive buzzer needs frequency)
pwm = GPIO.PWM(18, 1000)  # 1000 Hz tone

print("PWM beep 1...")
pwm.start(50)  # 50% duty cycle
time.sleep(0.4)
pwm.stop()
time.sleep(0.2)

print("PWM beep 2...")
pwm.start(50)
time.sleep(0.4)
pwm.stop()
time.sleep(0.2)

print("PWM beep 3...")
pwm.start(50)
time.sleep(0.4)
pwm.stop()

GPIO.cleanup()
print("PWM test done")
"""

c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect('192.168.137.38', username='pi', password='qwerty123', timeout=15)

sftp = c.open_sftp()
sftp.putfo(io.BytesIO(SCRIPT), '/tmp/buzz_test.py')
sftp.close()

print("Trying PWM (1000 Hz) on GPIO 18 — 3 tones...")
_, o, e = c.exec_command('python3 /tmp/buzz_test.py 2>&1', timeout=15)
print((o.read() + e.read()).decode('utf-8', 'replace').strip())

c.exec_command('nohup bash -c "cd ~/iot-demo && python pi_sensor_publisher.py > /tmp/publisher.log 2>&1 &" &')
c.close()
