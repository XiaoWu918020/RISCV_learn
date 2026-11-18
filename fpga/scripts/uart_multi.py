# -*- coding: utf-8 -*-
"""
uart_multi.py —— 同时监听多个串口（115200 8N1），用于不确定接在 CH342 哪个通道
用法: python uart_multi.py COM3 COM4 --sec 12
"""
import sys
import time
import argparse
import serial


def main(ports, seconds):
    handles = {}
    for name in ports:
        try:
            s = serial.Serial(name, 115200, timeout=0.1)
            s.reset_input_buffer()
            handles[name] = s
            print(f"# open {name} OK")
        except Exception as e:
            print(f"# open {name} FAILED: {e}")

    print(f"# listening {seconds}s ... 请现在按一次 PL_BUT 复位")
    t_end = time.time() + seconds
    totals = {n: 0 for n in handles}
    while time.time() < t_end:
        for name, s in handles.items():
            data = s.read(256)
            if data:
                totals[name] += len(data)
                txt = data.decode("ascii", errors="replace")
                print(f"[{name}] {txt}", end="")
                print(f"   [raw {len(data)}B] {data.hex()}")
    for name, s in handles.items():
        s.close()
    print(f"\n# done. totals = {totals}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("ports", nargs="+")
    ap.add_argument("--sec", type=float, default=12.0)
    a = ap.parse_args()
    main(a.ports, a.sec)
