import paramiko

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.137.38', username='pi', password='qwerty123', timeout=15)

def run(cmd):
    _, stdout, stderr = client.exec_command(cmd, timeout=20)
    out = stdout.read().decode('utf-8', errors='replace').strip()
    err = stderr.read().decode('utf-8', errors='replace').strip()
    return out or err

print("=== Pi Status ===")
print("Hostname :", run('hostname'))
print("IP       :", run('hostname -I'))
print("Uptime   :", run('uptime -p'))
print()
print("=== Docker containers ===")
print(run("docker ps --format 'table {{.Names}}\t{{.Status}}' 2>&1"))
print()
print("=== Project folder ===")
print(run("ls ~/iot-demo/ 2>/dev/null || ls ~/IOT_Project/ 2>/dev/null || ls ~/ 2>/dev/null | head -20"))

client.close()
