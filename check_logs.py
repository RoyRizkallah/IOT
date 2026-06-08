import paramiko

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.137.38', username='pi', password='qwerty123', timeout=15)

def run(cmd, timeout=20):
    _, stdout, stderr = client.exec_command(cmd, timeout=timeout)
    return (stdout.read() + stderr.read()).decode('utf-8', errors='replace').strip()

print("=== Is publisher still running? ===")
print(run("pgrep -a -f pi_sensor_publisher || echo 'NOT running'"))

print("\n=== publisher.log ===")
print(run("cat /tmp/publisher.log 2>/dev/null || echo 'no log file'"))

print("\n=== nohup.out (fallback) ===")
print(run("cat ~/nohup.out 2>/dev/null | tail -20 || echo 'no nohup.out'"))

print("\n=== Restart publisher directly and capture output ===")
print(run("cd ~/iot-demo && source venv/bin/activate 2>/dev/null; timeout 6 python pi_sensor_publisher.py 2>&1 | head -20"))

client.close()
