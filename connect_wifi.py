import paramiko, time, sys

c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect('192.168.137.38', username='pi', password='qwerty123', timeout=15)

def run(cmd, timeout=30):
    _, o, e = c.exec_command(cmd, timeout=timeout)
    return (o.read() + e.read()).decode('ascii', 'replace').strip()

print('=== Available networks ===')
result = run('nmcli -t -f SSID,SIGNAL dev wifi list ifname wlan0 2>&1')
print(result)

c.close()
