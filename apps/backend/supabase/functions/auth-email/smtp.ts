/// Minimal SMTP client for the auth-email hook. Hand-rolled on
/// Deno.connect / Deno.startTls / Deno.connectTls rather than a
/// deno.land/x mailer — third-party Deno tags aren't immutable (see
/// _shared/webhook_security.ts for the precedent), and the protocol
/// surface we need is five commands.
///
/// TLS posture mirrors the Go worker's net/smtp behaviour: port 465 →
/// implicit TLS; otherwise plaintext connect, then opportunistic
/// STARTTLS when the server advertises it. The local Mailpit catcher
/// (host.docker.internal:54325) advertises neither and takes mail
/// unauthenticated; a production relay (Resend / SES on 465/587)
/// negotiates TLS and AUTH PLAIN.

import { extractAddr } from './lib.ts';

export interface SmtpOptions {
  host: string;
  port: number;
  username?: string;
  password?: string;
  from: string;
  timeoutMs?: number;
}

interface SmtpReply {
  code: number;
  lines: string[];
}

class SmtpConn {
  private buffer = '';
  private decoder = new TextDecoder();
  private encoder = new TextEncoder();
  private reader: ReadableStreamDefaultReader<Uint8Array>;
  private writer: WritableStreamDefaultWriter<Uint8Array>;

  constructor(public conn: Deno.Conn) {
    this.reader = conn.readable.getReader();
    this.writer = conn.writable.getWriter();
  }

  // Re-wrap after a STARTTLS upgrade — the old reader/writer belong to
  // the plaintext stream.
  upgrade(conn: Deno.Conn) {
    this.conn = conn;
    this.reader = conn.readable.getReader();
    this.writer = conn.writable.getWriter();
    this.buffer = '';
  }

  async readReply(): Promise<SmtpReply> {
    for (;;) {
      const complete = this.tryParseReply();
      if (complete) return complete;
      const { value, done } = await this.reader.read();
      if (done) throw new Error('smtp: connection closed mid-reply');
      this.buffer += this.decoder.decode(value, { stream: true });
    }
  }

  private tryParseReply(): SmtpReply | null {
    const lines: string[] = [];
    let rest = this.buffer;
    for (;;) {
      const nl = rest.indexOf('\r\n');
      if (nl === -1) return null;
      const line = rest.slice(0, nl);
      rest = rest.slice(nl + 2);
      lines.push(line);
      if (/^\d{3} /.test(line) || /^\d{3}$/.test(line)) {
        this.buffer = rest;
        return { code: Number.parseInt(line.slice(0, 3), 10), lines };
      }
      if (!/^\d{3}-/.test(line)) {
        throw new Error('smtp: malformed reply line');
      }
    }
  }

  async write(data: string): Promise<void> {
    await this.writer.write(this.encoder.encode(data));
  }

  async cmd(line: string, expect: number): Promise<SmtpReply> {
    await this.write(line + '\r\n');
    const reply = await this.readReply();
    if (reply.code !== expect) {
      // The failing command is named, its argument (an address) is not —
      // SMTP errors flow to shared function logs.
      throw new Error(
        `smtp: ${line.split(' ')[0] || line} failed with ${reply.code}`,
      );
    }
    return reply;
  }

  release() {
    try {
      this.reader.releaseLock();
    } catch { /* already released */ }
    try {
      this.writer.releaseLock();
    } catch { /* already released */ }
  }
}

function dotStuff(mime: string): string {
  return mime
    .split('\r\n')
    .map((l) => (l.startsWith('.') ? '.' + l : l))
    .join('\r\n');
}

export async function smtpSend(
  opts: SmtpOptions,
  to: string,
  mime: string,
): Promise<void> {
  const timeoutMs = opts.timeoutMs ?? 15_000;
  let conn: Deno.Conn | null = null;
  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    try {
      conn?.close();
    } catch { /* already closed */ }
  }, timeoutMs);

  try {
    conn = opts.port === 465
      ? await Deno.connectTls({ hostname: opts.host, port: opts.port })
      : await Deno.connect({ hostname: opts.host, port: opts.port });
    const smtp = new SmtpConn(conn);

    const greeting = await smtp.readReply();
    if (greeting.code !== 220) throw new Error(`smtp: greeting ${greeting.code}`);

    const ehlo = await smtp.cmd('EHLO threkir.com', 250);
    const caps = ehlo.lines.map((l) => l.slice(4).trim().toUpperCase());

    if (opts.port !== 465 && caps.includes('STARTTLS')) {
      await smtp.cmd('STARTTLS', 220);
      smtp.release();
      const tlsConn = await Deno.startTls(conn as Deno.TcpConn, {
        hostname: opts.host,
      });
      conn = tlsConn;
      smtp.upgrade(tlsConn);
      await smtp.cmd('EHLO threkir.com', 250);
    }

    if (opts.username && opts.password) {
      const plain = btoa('\u0000' + opts.username + '\u0000' + opts.password);
      await smtp.cmd(`AUTH PLAIN ${plain}`, 235);
    }

    await smtp.cmd(`MAIL FROM:<${extractAddr(opts.from)}>`, 250);
    await smtp.cmd(`RCPT TO:<${to.trim()}>`, 250);
    await smtp.cmd('DATA', 354);
    await smtp.write(dotStuff(mime));
    if (!mime.endsWith('\r\n')) await smtp.write('\r\n');
    await smtp.cmd('.', 250);
    await smtp.write('QUIT\r\n');
    smtp.release();
  } catch (err) {
    if (timedOut) throw new Error('smtp: send timed out');
    throw err;
  } finally {
    clearTimeout(timer);
    try {
      conn?.close();
    } catch { /* already closed */ }
  }
}
