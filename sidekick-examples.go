package main

import (
	"fmt"
	"strings"
)

// Sidekick / Copilot / Blink workflow lab.
//
// Open this file in Neovim and use it as a disposable buffer for validating:
// - Blink completion menu priority on <Tab>
// - Copilot inline completion fallback on <Tab>
// - Sidekick NES automatic next-edit suggestions
// - LSP rename for semantic refactors that NES should not be expected to handle
//
// Suggested keys in this config:
// - <Tab>: accept visible Blink item, else Sidekick NES / Copilot inline, else indent
// - <C-y>: accept Blink item directly
// - <leader>asu: manually request Sidekick NES
// - <leader>asj: jump/apply active NES
// - LSP rename keymap: use your normal rename binding for semantic renames

type LabUser struct {
	Name   string
	Age    int
	Active bool
	Rating float64
	Scores []int
}

func averageScore(scores []int) float64 {
	if len(scores) == 0 {
		return 0
	}

	total := 0
	for _, score := range scores {
		total += score
	}
	return float64(total) / float64(len(scores))
}

// Exercise 1: LSP rename baseline.
// Rename processWorkflowUser with the LSP rename command, not NES.
// Expected: both call sites in main update reliably.
func processWorkflowUser(user LabUser) string {
	return fmt.Sprintf(
		"User: %s, Age: %d, Active: %t, Rating: %.2f, Avg Score: %.2f",
		user.Name,
		user.Age,
		user.Active,
		user.Rating,
		averageScore(user.Scores),
	)
}

// Exercise 2: NES local pattern propagation.
// Change only the first label below from "Status" to "State", then leave insert mode.
// Expected: automatic NES may suggest the same local label change on the next lines.
// If nothing appears, try <leader>asu while the cursor is inside this function.
func renderStatusPanel(user LabUser) []string {
	return []string{
		fmt.Sprintf("Status: name=%s", user.Name),
		fmt.Sprintf("Status: active=%t", user.Active),
		fmt.Sprintf("Status: rating=%.2f", user.Rating),
	}
}

// Exercise 3: NES repeated shape propagation.
// Change the first "profile" word in the rendered text to "account".
// Expected: NES is more likely to help here than with a semantic function rename,
// because the related edits are nearby and text-pattern based.
func renderProfileSummary(user LabUser) string {
	lines := []string{
		fmt.Sprintf("profile name: %s", user.Name),
		fmt.Sprintf("profile age: %d", user.Age),
		fmt.Sprintf("profile rating: %.2f", user.Rating),
	}
	return strings.Join(lines, "\n")
}

// Exercise 4: Copilot inline completion.
// Put the cursor after "return" and start typing a natural-language-ish expression,
// for example: return fmt.Sprintf("%s has
// Expected: Copilot inline should suggest the rest. <Tab> accepts it when Blink is not visible.
func inlineCompletionExercise(user LabUser) string {
	return fmt.Sprintf("%s has %.2f average score", user.Name, averageScore(user.Scores))
}

// Exercise 5: Blink completion priority.
// Inside this function, type "fmt." or "user." and confirm the Blink menu appears.
// Expected: when the menu is visible, <Tab> accepts Blink before NES or Copilot inline.
func blinkCompletionExercise(user LabUser) string {
	return fmt.Sprintf("%s:%t", user.Name, user.Active)
}

func main() {
	shahe := LabUser{
		Name:   "Shahe",
		Age:    34,
		Active: true,
		Rating: 4.8,
		Scores: []int{8, 9, 10},
	}

	fmt.Println(processWorkflowUser(shahe))
	fmt.Println(processWorkflowUser(LabUser{Name: "Second User", Scores: []int{5, 6, 7}}))
	fmt.Println(strings.Join(renderStatusPanel(shahe), " | "))
	fmt.Println(renderProfileSummary(shahe))
	fmt.Println(inlineCompletionExercise(shahe))
	fmt.Println(blinkCompletionExercise(shahe))
}
