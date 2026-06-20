package digesttoken

import "testing"

func TestMintVerify_RoundTrip(t *testing.T) {
	tok := Mint("s3cret", StreamWeeklyDigest, "user-1")
	if tok == "" {
		t.Fatal("mint returned empty token for valid inputs")
	}
	if !Verify("s3cret", StreamWeeklyDigest, "user-1", tok) {
		t.Error("a freshly minted token must verify")
	}
}

func TestVerify_WrongUserFails(t *testing.T) {
	tok := Mint("s3cret", StreamWeeklyDigest, "user-1")
	if Verify("s3cret", StreamWeeklyDigest, "user-2", tok) {
		t.Error("a token minted for user-1 must not verify for user-2")
	}
}

func TestVerify_WrongSecretFails(t *testing.T) {
	tok := Mint("s3cret", StreamWeeklyDigest, "user-1")
	if Verify("other", StreamWeeklyDigest, "user-1", tok) {
		t.Error("a token minted under one secret must not verify under another")
	}
}

func TestVerify_WrongStreamFails(t *testing.T) {
	// A token minted for the weekly digest must NOT verify against the
	// lifecycle drip — the stream namespaces the MAC so one engagement
	// stream's unsubscribe link can't be replayed against another.
	tok := Mint("s3cret", StreamWeeklyDigest, "user-1")
	if Verify("s3cret", StreamLifecycleDrip, "user-1", tok) {
		t.Error("a weekly-digest token must not verify for the lifecycle drip")
	}
	drip := Mint("s3cret", StreamLifecycleDrip, "user-1")
	if Verify("s3cret", StreamWeeklyDigest, "user-1", drip) {
		t.Error("a lifecycle-drip token must not verify for the weekly digest")
	}
}

func TestVerify_TamperedTokenFails(t *testing.T) {
	tok := Mint("s3cret", StreamWeeklyDigest, "user-1")
	// Flip the last character.
	bad := tok[:len(tok)-1]
	if tok[len(tok)-1] == 'A' {
		bad += "B"
	} else {
		bad += "A"
	}
	if Verify("s3cret", StreamWeeklyDigest, "user-1", bad) {
		t.Error("a tampered token must not verify")
	}
}

func TestVerify_FailsClosedOnEmptyInputs(t *testing.T) {
	tok := Mint("s3cret", StreamWeeklyDigest, "user-1")
	cases := []struct {
		name                     string
		secret, stream, uid, tok string
	}{
		{"empty secret", "", StreamWeeklyDigest, "user-1", tok},
		{"empty stream", "s3cret", "", "user-1", tok},
		{"empty user", "s3cret", StreamWeeklyDigest, "", tok},
		{"empty token", "s3cret", StreamWeeklyDigest, "user-1", ""},
		{"all empty", "", "", "", ""},
	}
	for _, c := range cases {
		if Verify(c.secret, c.stream, c.uid, c.tok) {
			t.Errorf("%s: must fail closed", c.name)
		}
	}
}

func TestVerify_MalformedBase64Fails(t *testing.T) {
	if Verify("s3cret", StreamWeeklyDigest, "user-1", "not valid base64url!!!") {
		t.Error("a non-base64url token must not verify")
	}
}

func TestMint_EmptyInputsReturnEmpty(t *testing.T) {
	if Mint("", StreamWeeklyDigest, "user-1") != "" {
		t.Error("empty secret should mint empty")
	}
	if Mint("s3cret", "", "user-1") != "" {
		t.Error("empty stream should mint empty")
	}
	if Mint("s3cret", StreamWeeklyDigest, "") != "" {
		t.Error("empty user should mint empty")
	}
}

func TestMint_TokenCarriesNoPII(t *testing.T) {
	// The user id must not appear verbatim in the token (it's the MAC
	// input, not the payload). A token that leaked the id would let an
	// observer enumerate recipients from intercepted unsubscribe links.
	uid := "abcdef01-2345-6789-abcd-ef0123456789"
	tok := Mint("s3cret", StreamWeeklyDigest, uid)
	if tok == "" {
		t.Fatal("unexpected empty token")
	}
	if containsSubstring(tok, uid) {
		t.Error("token must not embed the user id verbatim")
	}
}

func containsSubstring(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
