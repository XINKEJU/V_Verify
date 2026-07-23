package main

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/sha256"
	_ "embed"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"runtime"
	"strings"
	"syscall"
)

//go:embed index.html.enc
var encryptedHTML []byte

// 编译时内嵌的解密密钥（32 字节 Fernet 密钥，hex 编码）
var encKeyHex = "8bfcd0a964a29d22bd23879282824a576fe32bdfa759480d8565658c51237a18"

func fernetDecrypt(token []byte, key []byte) ([]byte, error) {
	if len(key) != 32 {
		return nil, fmt.Errorf("invalid key length")
	}
	// key split: signing_key (16) + encryption_key (16)
	signingKey := key[:16]
	encryptionKey := key[16:]

	// Fernet token format: Version(1) + Timestamp(8) + IV(16) + Ciphertext + HMAC(32)
	if len(token) < 1+8+16+32 {
		return nil, fmt.Errorf("token too short")
	}

	hmacData := token[:len(token)-32]
	givenHMAC := token[len(token)-32:]

	// Verify HMAC
	mac := hmac.New(sha256.New, signingKey)
	mac.Write(hmacData)
	expectedHMAC := mac.Sum(nil)
	if !hmac.Equal(givenHMAC, expectedHMAC) {
		return nil, fmt.Errorf("HMAC verification failed")
	}

	if token[0] != 0x80 {
		return nil, fmt.Errorf("unsupported version")
	}

	iv := token[1+8 : 1+8+16]
	ciphertext := token[1+8+16 : len(token)-32]

	block, err := aes.NewCipher(encryptionKey)
	if err != nil {
		return nil, err
	}

	mode := cipher.NewCBCDecrypter(block, iv)
	plaintext := make([]byte, len(ciphertext))
	mode.CryptBlocks(plaintext, ciphertext)

	// PKCS7 unpad
	if len(plaintext) == 0 {
		return nil, fmt.Errorf("empty plaintext")
	}
	padLen := plaintext[len(plaintext)-1]
	if int(padLen) > len(plaintext) || padLen == 0 || padLen > 16 {
		return nil, fmt.Errorf("invalid padding")
	}
	for i := 1; i < int(padLen); i++ {
		if plaintext[len(plaintext)-1-i] != padLen {
			return nil, fmt.Errorf("invalid padding")
		}
	}
	return plaintext[:len(plaintext)-int(padLen)], nil
}

func main() {
	port := "39876"

	// 解密 HTML 内容
	key, _ := hex.DecodeString(encKeyHex)
	// Fernet token: base64url 编码（RFC 4648，无填充）
	tokenStr := string(encryptedHTML)
	tokenStr = strings.NewReplacer("-", "+", "_", "/").Replace(tokenStr)
	if m := len(tokenStr) % 4; m != 0 {
		tokenStr += strings.Repeat("=", 4-m)
	}
	token, _ := base64.StdEncoding.DecodeString(tokenStr)
	html, err := fernetDecrypt(token, key)
	if err != nil {
		panic("解密失败: " + err.Error())
	}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Write(html)
	})

	listener, err := net.Listen("tcp", ":"+port)
	if err != nil {
		listener, _ = net.Listen("tcp", ":0")
		port = fmt.Sprintf("%d", listener.Addr().(*net.TCPAddr).Port)
	}

	go http.Serve(listener, nil)

	url := "http://localhost:" + port
	fmt.Println("V计划学生信息认证 已启动:", url)

	switch runtime.GOOS {
	case "darwin":
		exec.Command("open", url).Start()
	case "windows":
		exec.Command("rundll32", "url.dll,FileProtocolHandler", url).Start()
	case "android":
		// Android: 使用 am start 打开默认浏览器
		exec.Command("am", "start", "-a", "android.intent.action.VIEW", "-d", url).Start()
	default:
		// Linux 及其他平台
		exec.Command("xdg-open", url).Start()
	}

	// 等待终止信号，保持进程运行但不阻塞事件循环
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	os.Exit(0)
}
