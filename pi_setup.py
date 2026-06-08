import paramiko, socket

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.settimeout(15)
sock.connect(('192.168.137.38', 22))

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.137.38', username='pi', password='qwerty123', sock=sock, timeout=15)

def run(cmd, timeout=15):
    stdin, stdout, stderr = client.exec_command(cmd, timeout=timeout)
    stdout.channel.settimeout(timeout)
    try:
        out = stdout.read().decode('utf-8', errors='replace')
    except Exception:
        out = "(timed out)"
    try:
        err = stderr.read().decode('utf-8', errors='replace')
    except Exception:
        err = ""
    return (out + err).strip()

print("=== Camera streamer loop (lines 200-300) ===")
print(run('sed -n "200,300p" ~/iot-demo/pi_camera_streamer.py'))

client.close()
