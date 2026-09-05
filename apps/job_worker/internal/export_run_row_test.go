package internal

import (
	"reflect"
	"sort"
	"strings"
	"testing"
)

// The select is what decides whether a column can reach the subject at all,
// and it is a string: a field added to ExportRunRow but not to the select
// decodes as null on every row, which is indistinguishable from a column the
// runner never wrote (decisions § 1171). dataexport's own guard holds the
// select to the table and to the Edge Function's; this one holds the struct
// to the select.
func TestExportRunRowMirrorsItsSelect(t *testing.T) {
	var want []string
	for _, c := range strings.Split(exportRunsSelect, ",") {
		if c = strings.TrimSpace(c); c != "" {
			want = append(want, c)
		}
	}
	sort.Strings(want)

	rt := reflect.TypeOf(ExportRunRow{})
	var got []string
	for i := 0; i < rt.NumField(); i++ {
		tag := strings.Split(rt.Field(i).Tag.Get("json"), ",")[0]
		if tag != "" && tag != "-" {
			got = append(got, tag)
		}
	}
	sort.Strings(got)

	if !reflect.DeepEqual(got, want) {
		t.Errorf("ExportRunRow and the select disagree.\n  select: %v\n  struct: %v", want, got)
	}
}
