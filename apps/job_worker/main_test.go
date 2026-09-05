package main

import (
	"encoding/json"
	"fmt"
	"reflect"
	"testing"

	"github.com/Absence0760/project-running/apps/job_worker/internal"
)

// exportRunFromRow is a hand-written field-by-field copy between two structs
// the leaf-package rule keeps apart, and a field forgotten in it is a column
// selected from the database and then dropped on the way to the archive --
// invisible to every downstream guard, because both ends agree about the
// column and only the bridge does not (decisions § 1171).
//
// Every field is filled with a distinct non-zero value first: a forgotten
// field copied as its zero value would otherwise compare equal to a source
// that happened to be zero too.
func TestExportRunFromRowCopiesEveryField(t *testing.T) {
	var row internal.ExportRunRow
	seed := 0
	fillDistinct(t, reflect.ValueOf(&row).Elem(), &seed)

	got := asMap(t, exportRunFromRow(row))
	want := asMap(t, row)
	if !reflect.DeepEqual(got, want) {
		for k, v := range want {
			if !reflect.DeepEqual(got[k], v) {
				t.Errorf("%s: bridged as %v, want %v", k, got[k], v)
			}
		}
		t.Fatalf("exportRunFromRow dropped or altered a field")
	}
}

func asMap(t *testing.T, v interface{}) map[string]interface{} {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	var m map[string]interface{}
	if err := json.Unmarshal(b, &m); err != nil {
		t.Fatal(err)
	}
	return m
}

func fillDistinct(t *testing.T, v reflect.Value, seed *int) {
	t.Helper()
	switch v.Kind() {
	case reflect.Struct:
		for i := 0; i < v.NumField(); i++ {
			fillDistinct(t, v.Field(i), seed)
		}
	case reflect.Pointer:
		p := reflect.New(v.Type().Elem())
		fillDistinct(t, p.Elem(), seed)
		v.Set(p)
	case reflect.Map:
		*seed++
		m := reflect.MakeMap(v.Type())
		m.SetMapIndex(reflect.ValueOf(fmt.Sprintf("k%d", *seed)), reflect.ValueOf(interface{}(float64(*seed))))
		v.Set(m)
	case reflect.String:
		*seed++
		v.SetString(fmt.Sprintf("v%d", *seed))
	case reflect.Int:
		*seed++
		v.SetInt(int64(*seed))
	case reflect.Float64:
		*seed++
		v.SetFloat(float64(*seed) + 0.5)
	case reflect.Bool:
		v.SetBool(true)
	default:
		t.Fatalf("fillDistinct has no case for %s; add one rather than leaving a field zero", v.Kind())
	}
}
