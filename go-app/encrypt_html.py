#!/usr/bin/env python3
"""
加密学信档案编辑器.html 为 Fernet 格式 (与 main.go 兼容)

Fernet token format: Version(1) + Timestamp(8) + IV(16) + Ciphertext + HMAC(32)
- Key split: signing_key (16) + encryption_key (16) = 32 bytes total
- AES-CBC + HMAC-SHA256
- 编码: base64url (no padding)
"""
import os, sys, base64, hmac, hashlib, time, struct

# 与 main.go 完全一致
ENC_KEY_HEX = "8bfcd0a964a29d22bd23879282824a576fe32bdfa759480d8565658c51237a18"

HTML_PATH = "/Users/xinkeju/Desktop/联通/学信档案编辑器.html"
OUT_PATH = "/Users/xinkeju/Desktop/联通/go-app/index.html.enc"


def pkcs7_pad(data: bytes, block_size: int = 16) -> bytes:
    pad_len = block_size - (len(data) % block_size)
    return data + bytes([pad_len]) * pad_len


def fernet_encrypt(plaintext: bytes, key: bytes) -> bytes:
    if len(key) != 32:
        raise ValueError("key must be 32 bytes")
    signing_key = key[:16]
    encryption_key = key[16:]

    version = b"\x80"
    timestamp = struct.pack(">Q", int(time.time()))  # 8 bytes
    iv = os.urandom(16)

    # AES-128-CBC
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    cipher = Cipher(algorithms.AES(encryption_key), modes.CBC(iv))
    encryptor = cipher.encryptor()
    ciphertext = encryptor.update(pkcs7_pad(plaintext)) + encryptor.finalize()

    body = version + timestamp + iv + ciphertext
    mac = hmac.new(signing_key, body, hashlib.sha256).digest()
    return body + mac


def b64url_encode(data: bytes) -> str:
    """Fernet 使用 base64url 编码（无填充）"""
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def main():
    if not os.path.exists(HTML_PATH):
        print(f"❌ 找不到源文件: {HTML_PATH}")
        sys.exit(1)

    with open(HTML_PATH, "rb") as f:
        html = f.read()

    key = bytes.fromhex(ENC_KEY_HEX)
    token = fernet_encrypt(html, key)
    encoded = b64url_encode(token)

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="ascii") as f:
        f.write(encoded)

    print(f"✅ 加密完成: {OUT_PATH}")
    print(f"   源文件: {len(html):,} bytes")
    print(f"   加密后: {len(encoded):,} bytes (base64url)")
    print(f"   原始:   {len(token):,} bytes (binary)")


if __name__ == "__main__":
    main()
