package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"
)

// ============================================================================
// TEST 1: Treesitter Textobjects
//
// Place cursor inside any function, then try:
//   vaf  → visually select the ENTIRE function (signature + body)
//   vif  → visually select just the function BODY (inside the braces)
//   daf  → delete the entire function
//   yif  → yank the function body
//   ]f   → jump to the NEXT function
//   [f   → jump to the PREVIOUS function
//
// Also try:  vaa/via (parameter), vac/vic (struct = class), val/vil (loop)
// ============================================================================

// Decoder wraps a json.Decoder with helpers.
type Decoder struct {
	reader *strings.Reader
	dec    *json.Decoder
}

// NewDecoder creates a Decoder from raw JSON bytes.
// Try: place cursor here, press ]f to jump to DecodeObject.
func NewDecoder(data []byte) *Decoder {
	r := strings.NewReader(string(data))
	return &Decoder{
		reader: r,
		dec:    json.NewDecoder(r),
	}
}

// DecodeObject decodes a single JSON object.
// Try: vaf to select this whole function, vif for just the body.
func (d *Decoder) DecodeObject(target interface{}) error {
	if err := d.dec.Decode(target); err != nil {
		return fmt.Errorf("decode failed: %w", err)
	}
	return nil
}

// DecodeIntoObject resets and decodes.
func (d *Decoder) DecodeIntoObject(data []byte, target interface{}) error {
	d.reader.Reset(string(data))
	d.dec = json.NewDecoder(d.reader)
	return d.DecodeObject(target)
}

// DecodeObjects decodes multiple JSON objects from a stream.
// Try: place cursor on the for loop, then vil to select the loop body.
func (d *Decoder) DecodeObjects(targets []interface{}) error {
	for i, target := range targets {
		if err := d.dec.Decode(target); err != nil {
			return fmt.Errorf("decode %d failed: %w", i, err)
		}
	}
	return nil
}

// ============================================================================
// TEST 2: Treesitter Injections (SQL + JSON in Go strings)
//
// If parsers are installed, the SQL and JSON below should be syntax-highlighted
// inside the Go strings — different colors for SELECT, FROM, WHERE, etc.
// ============================================================================

func queryUsers(db *sql.DB, name string) error {
	// This SQL should be highlighted inside the Go string:
	query := `
		SELECT u.id, u.name, u.email, u.created_at
		FROM users u
		INNER JOIN accounts a ON a.user_id = u.id
		WHERE u.name = $1
			AND a.status = 'active'
		ORDER BY u.created_at DESC
		LIMIT 100
	`
	rows, err := db.Query(query, name)
	if err != nil {
		return err
	}
	defer rows.Close()
	return nil
}

func buildConfig() string {
	// This JSON should be highlighted inside the Go string:
	return `{
		"apiVersion": "cilium.io/v2",
		"kind": "CiliumNetworkPolicy",
		"metadata": {
			"name": "allow-dns",
			"namespace": "production"
		},
		"spec": {
			"endpointSelector": {
				"matchLabels": {
					"app": "api-server"
				}
			}
		}
	}`
}

// ============================================================================
// TEST 3: LSP Call Hierarchy
//
// Place cursor on "DecodeObject" in the function below, then:
//   <leader>ci  → fzf-lua picker showing who calls DecodeObject
//   <leader>cI  → tree view showing the full incoming call chain
//   <leader>co  → fzf-lua picker showing what DecodeObject calls
//   <leader>cO  → tree view showing the full outgoing call chain
//
// In the tree view:
//   o     → expand/collapse a node
//   <CR>  → jump to that function's definition
//   q     → close the tree
// ============================================================================

func processAll(data [][]byte) error {
	for _, d := range data {
		dec := NewDecoder(d)
		var result map[string]interface{}
		if err := dec.DecodeObject(&result); err != nil {
			return err
		}
		fmt.Println(result)
	}
	return nil
}

func handleRequest(payload []byte) error {
	dec := NewDecoder(payload)
	var obj map[string]interface{}
	return dec.DecodeObject(&obj)
}

// ============================================================================
// TEST 4: Treesitter-aware gw/gq
//
// This is best tested in a MARKDOWN file with embedded code blocks.
// Create a .md file with a lua code block containing long comments,
// then use gqip inside the code block to reformat.
// ============================================================================

func main() {
	data := []byte(`{"name": "test", "value": 42}`)
	dec := NewDecoder(data)
	var result map[string]interface{}
	if err := dec.DecodeObject(&result); err != nil {
		fmt.Println("Error:", err)
		return
	}
	fmt.Println(result)
}
