"""Add manual buzzer trigger via MQTT control command on the Pi."""
import paramiko, io

PATCH = r'''
        if "buzzer" in data:
            if data["buzzer"] is True:
                print("[BUZZER] Manual trigger from app!")
                t = threading.Thread(target=_buzzer_sequence, daemon=True)
                t.start()
            elif data["buzzer"] is False:
                if has_gpio and buzzer_hw:
                    try: buzzer_hw.off()
                    except Exception: pass
                print("[BUZZER] Manual stop from app.")
'''

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.137.38', username='pi', password='qwerty123', timeout=15)

def run(cmd, timeout=20):
    _, stdout, stderr = client.exec_command(cmd, timeout=timeout)
    return (stdout.read() + stderr.read()).decode('utf-8', errors='replace').strip()

# Read current file
sftp = client.open_sftp()
with sftp.open('/home/pi/iot-demo/pi_sensor_publisher.py', 'r') as f:
    content = f.read().decode('utf-8')

# Insert manual buzzer handling inside on_message, after buzzer_threshold block
insert_after = '            print(f"Buzzer threshold updated \u2192 {TEMP_BUZZER_THRESHOLD}\u00b0C")'
if insert_after not in content:
    # fallback anchor
    insert_after = 'print(f"Buzzer threshold updated'

updated = content.replace(insert_after, insert_after + PATCH)

if updated == content:
    print("WARNING: anchor not found, appending patch manually")
    # Find on_message and add before the except
    updated = content.replace(
        '    except Exception as e:\n        print("Error processing control command:", e)',
        PATCH + '    except Exception as e:\n        print("Error processing control command:", e)',
        1
    )

sftp.putfo(io.BytesIO(updated.encode()), '/home/pi/iot-demo/pi_sensor_publisher.py')
sftp.close()

print("Patched on_message to handle {buzzer: true/false} commands.")
print("Verify:", run("grep -n 'Manual trigger' ~/iot-demo/pi_sensor_publisher.py"))
client.close()
