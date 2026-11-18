# -*- coding: utf-8 -*-
"""
uart_capture.py —— 监听 RISC-V 板级 UART 输出（115200 8N1）
用法:
  python uart_capture.py --list              # 列出所有串口
  python uart_capture.py --port COM3 --sec 8 # 监听指定串口 8 秒
"""
import sys
import argparse
import serial  # pyserial


def list_ports():
    from serial.tools import list_ports
    ports = list(list_ports.comports())
    if not ports:
        print("(no serial ports)")
    for p in ports:
        print(f"{p.device:8}  {p.description}  hwid={p.hwid}")


def capture(port_name: str, seconds: float):
    # 115200 8N1, 无流控；先 DTR/RTS 不强制
    ser = serial.Serial(
        port=port_name,
        baudrate=115200,
        bytesize=serial.EIGHTBITS,
        parity=serial.PARITY_NONE,
        stopbits=serial.STOPBITS_ONE,
        timeout=0.2,
    )
    print(f"# open {port_name} @115200 8N1, capture {seconds}s ...")
    ser.reset_input_buffer()

    import time
    t_end = time.time() + seconds
    total = 0
    while time.time() < t_end:
        data = ser.read(256)
        if data:
            total += len(data)
            # 文本输出（替换非法字节，避免崩溃）
            txt = data.decode("ascii", errors="replace")
            sys.stdout.write(txt)
            sys.stdout.flush()
            # 同时给出原始 hex，便于发现非 ASCII / 波特率异常
            print(f"\n   [raw {len(data)}B] {data.hex()}")
    ser.close()
    print(f"\n# done, total bytes = {total}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--port", default=None)
    ap.add_argument("--sec", type=float, default=8.0)
    args = ap.parse_args()
    if args.list:
        list_ports()
    elif args.port:
        capture(args.port, args.sec)
    else:
        ap.print_help()
