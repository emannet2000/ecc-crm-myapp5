package main

import (
	"bufio"
	"encoding/base64"
	"fmt"
	"io"
	"net"
	"net/mail"
	"net/textproto"
	"strings"
	"testing"
	"time"
)

// Exercise the real SMTP transport and outbox worker against a local inbox.
// This is controlled delivery evidence, not acceptance of an external provider.
func TestSMTPOutboxRejectsThenDeliversRetryOnce(t *testing.T) {
	setupStore(t)
	user, _ := findUserByEmail("demo@northwind.dev")
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	type receivedMail struct {
		recipient string
		body      []byte
	}
	inbox := make(chan receivedMail, 2)
	errors := make(chan error, 2)
	done := make(chan struct{})
	go func() {
		defer close(done)
		for attempt := 0; ; attempt++ {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			conn.SetDeadline(time.Now().Add(5 * time.Second))
			reader := textproto.NewReader(bufio.NewReader(conn))
			reply := func(line string) error { _, err := fmt.Fprintf(conn, "%s\r\n", line); return err }
			if err := reply("220 local acceptance inbox"); err != nil {
				errors <- err
				conn.Close()
				continue
			}
			recipient := ""
			for {
				line, err := reader.ReadLine()
				if err != nil {
					if err != io.EOF {
						errors <- err
					}
					break
				}
				switch {
				case strings.HasPrefix(line, "EHLO"), strings.HasPrefix(line, "HELO"), strings.HasPrefix(line, "MAIL FROM:"):
					err = reply("250 OK")
				case strings.HasPrefix(line, "RCPT TO:"):
					if attempt == 0 {
						err = reply("550 temporary fixture rejection")
					} else {
						recipient = strings.TrimPrefix(line, "RCPT TO:")
						err = reply("250 OK")
					}
				case line == "DATA":
					if err = reply("354 End with a dot"); err == nil {
						var body []byte
						body, err = reader.ReadDotBytes()
						if err == nil {
							inbox <- receivedMail{recipient: recipient, body: body}
							err = reply("250 Accepted")
						}
					}
				case line == "QUIT":
					reply("221 Bye")
					conn.Close()
					goto nextConnection
				default:
					err = reply("250 OK")
				}
				if err != nil {
					errors <- err
					break
				}
			}
			conn.Close()
		nextConnection:
		}
	}()
	t.Cleanup(func() { listener.Close(); <-done })
	_, port, _ := net.SplitHostPort(listener.Addr().String())
	t.Setenv("SMTP_HOST", "127.0.0.1")
	t.Setenv("SMTP_PORT", port)
	t.Setenv("SMTP_TLS_MODE", "local")
	t.Setenv("SMTP_FROM", "ECC Test <sender@example.invalid>")
	t.Setenv("SMTP_USER", "")
	t.Setenv("SMTP_PASSWORD", "")
	recipient, subject, body := "inbox@example.invalid", "Local SMTP acceptance", "Retry this exact message once."
	if err := queueMail(aiUserRequest(t.Context(), user), user, "client", recipient, subject, body, "", ""); err != nil {
		t.Fatal(err)
	}
	deliverMailOutbox()
	var status string
	var attempts int
	if err := database.QueryRow("SELECT status,attempts FROM mail_outbox WHERE subject=?", subject).Scan(&status, &attempts); err != nil {
		t.Fatal(err)
	}
	if status != "queued" || attempts != 1 {
		t.Fatalf("rejection should queue a retry, got %s attempts=%d", status, attempts)
	}
	if len(inbox) != 0 {
		t.Fatal("rejected recipient received mail")
	}
	if _, err := database.Exec("UPDATE mail_outbox SET next_attempt='' WHERE subject=?", subject); err != nil {
		t.Fatal(err)
	}
	deliverMailOutbox()
	if err := database.QueryRow("SELECT status FROM mail_outbox WHERE subject=?", subject).Scan(&status); err != nil {
		t.Fatal(err)
	}
	if status != "sent" {
		t.Fatalf("successful SMTP delivery should record sent, got %s", status)
	}
	select {
	case message := <-inbox:
		if message.recipient != "<"+recipient+">" {
			t.Fatalf("wrong envelope recipient: %s", message.recipient)
		}
		parsed, err := mail.ReadMessage(strings.NewReader(string(message.body)))
		if err != nil {
			t.Fatal(err)
		}
		decoded, err := io.ReadAll(base64.NewDecoder(base64.StdEncoding, parsed.Body))
		if err != nil {
			t.Fatal(err)
		}
		if parsed.Header.Get("To") != recipient || string(decoded) != body {
			t.Fatal("delivered recipient or body differs from queued mail")
		}
	case err := <-errors:
		t.Fatal(err)
	case <-time.After(2 * time.Second):
		t.Fatal("SMTP inbox did not receive the queued message")
	}
	deliverMailOutbox()
	if len(inbox) != 0 {
		t.Fatal("worker redelivered a completed message")
	}
	select {
	case err := <-errors:
		t.Fatal(err)
	default:
	}
}
