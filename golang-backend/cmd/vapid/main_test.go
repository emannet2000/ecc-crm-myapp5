package main

import (
	"crypto/elliptic"
	"encoding/base64"
	"io"
	"math/big"
	"os"
	"strings"
	"testing"
)

func TestGeneratedVAPIDKeysAreAMatchingP256Pair(t *testing.T) {
	original := os.Stdout
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	defer reader.Close()
	defer func() { os.Stdout = original; writer.Close() }()
	os.Stdout = writer
	main()
	writer.Close()
	os.Stdout = original
	output, err := io.ReadAll(reader)
	if err != nil {
		t.Fatal(err)
	}
	values := map[string]string{}
	for _, line := range strings.Split(strings.TrimSpace(string(output)), "\n") {
		key, value, ok := strings.Cut(line, "=")
		if !ok {
			t.Fatal("key generator emitted malformed configuration")
		}
		values[key] = value
	}
	public, err := base64.RawURLEncoding.DecodeString(values["VAPID_PUBLIC_KEY"])
	if err != nil {
		t.Fatal(err)
	}
	private, err := base64.RawURLEncoding.DecodeString(values["VAPID_PRIVATE_KEY"])
	if err != nil {
		t.Fatal(err)
	}
	curve := elliptic.P256()
	scalar := new(big.Int).SetBytes(private)
	if len(private) != 32 || scalar.Sign() <= 0 || scalar.Cmp(curve.Params().N) >= 0 {
		t.Fatal("invalid VAPID private scalar")
	}
	x, y := elliptic.Unmarshal(curve, public)
	if x == nil || y == nil || !curve.IsOnCurve(x, y) {
		t.Fatal("invalid VAPID public point")
	}
	expectedX, expectedY := curve.ScalarBaseMult(private)
	if x.Cmp(expectedX) != 0 || y.Cmp(expectedY) != 0 {
		t.Fatal("VAPID public/private keys do not match")
	}
}
