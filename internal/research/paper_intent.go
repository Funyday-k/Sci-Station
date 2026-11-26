package research

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"
)

var (
	chinesePaperOrdinal = regexp.MustCompile(`第\s*([0-9]{1,5}|[零〇一二两三四五六七八九十]{1,4})\s*篇(?:\s*(?:论文|文章|文献))?`)
	englishPaperOrdinal = regexp.MustCompile(`(?i)\b(first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|[0-9]{1,5}(?:st|nd|rd|th))\s+(?:research\s+)?(?:paper|article)\b`)
	numberedFigure      = regexp.MustCompile(`(?i)(?:\bfig(?:ure)?\.?\s*|图\s*)[（(]?([0-9]+[a-z]?)\b`)
	numberedEquation    = regexp.MustCompile(`(?i)(?:\beq(?:uation)?\.?\s*|公式\s*|方程\s*|式\s*)[（(]?([0-9]+[a-z]?)\b`)
	formulaQuestion     = regexp.MustCompile(`(?i)\b(?:equations?|eq\.|formula(?:s|e)?)\b|公式|方程`)
	paperQuestion       = regexp.MustCompile(`(?i)\b(?:this|that|the|current|selected)\s+(?:research\s+)?(?:paper|article)\b|(?:这|该|本|所选)篇?(?:论文|文章|文献)`)
	sectionQuestion     = regexp.MustCompile(`(?i)\b(abstract|introduction|methods?|results?|conclusions?|discussion|limitations?)\b|摘要|引言|介绍|方法|结果|结论|讨论|局限`)
	equationEnvironment = regexp.MustCompile(`\\begin\{((?:equation|align|aligned|eqnarray|gather|multline)\*?)\}`)
	equationTag         = regexp.MustCompile(`\\tag\*?\{([0-9]+[a-z]?)\}|[（(]([0-9]+[a-z]?)[）)]\s*$`)
	inlineEquation      = regexp.MustCompile(`\$[^$\n]+\$|\\\([^\n]+?\\\)`)
	equationRelation    = regexp.MustCompile(`=|\\(?:[aA]pprox|simeq|equiv|propto|leq?|geq?|neq)\b`)
)

// PaperQuestionSelection has already been selected by the user. The attachment
// API independently verifies its hash and exact bytes before using it.
type PaperQuestionSelection struct {
	SourceLocation
	Quote string
}

type PaperQuestion struct {
	Text, Project, CurrentPaper string
	// nil means the project library's default order. An empty non-nil list
	// represents the empty, filtered library currently visible in the sidebar.
	VisiblePaperIDs []string
	Selected        []PaperQuestionSelection
}

type PaperPassage struct {
	SourceLocation
	Title   string `json:"title"`
	Line    int    `json:"line"`
	EndLine int    `json:"endLine"`
	Heading string `json:"heading,omitempty"`
	Hash    string `json:"hash"`
	Quote   string `json:"quote"`
}

type paperQuestionIntent struct {
	ordinals               []int
	figures, equations     []string
	formula, refersToPaper bool
	section                string
	terms                  []string
}

func parsePaperQuestion(question string) paperQuestionIntent {
	intent := paperQuestionIntent{
		formula:       formulaQuestion.MatchString(question),
		refersToPaper: paperQuestion.MatchString(question),
		section:       strings.ToLower(sectionQuestion.FindString(question)),
	}
	query := question
	for _, pattern := range []*regexp.Regexp{chinesePaperOrdinal, englishPaperOrdinal} {
		for _, match := range pattern.FindAllStringSubmatch(question, -1) {
			num := paperOrdinal(strings.ToLower(match[1]))
			if !slices.Contains(intent.ordinals, num) {
				intent.ordinals = append(intent.ordinals, num)
			}
		}
		query = pattern.ReplaceAllString(query, " ")
	}
	for _, match := range numberedFigure.FindAllStringSubmatch(question, -1) {
		label := strings.ToLower(match[1])
		if !slices.Contains(intent.figures, label) {
			intent.figures = append(intent.figures, label)
		}
	}
	for _, match := range numberedEquation.FindAllStringSubmatch(question, -1) {
		label := strings.ToLower(match[1])
		if !slices.Contains(intent.equations, label) {
			intent.equations = append(intent.equations, label)
		}
	}
	query = numberedFigure.ReplaceAllString(numberedEquation.ReplaceAllString(query, " "), " ")
	intent.terms = paperQuestionTerms(query)
	return intent
}

func paperOrdinal(word string) int {
	if i := slices.Index([]string{"first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"}, word); i >= 0 {
		return i + 1
	}
	if n, err := strconv.Atoi(strings.TrimRight(word, "stndrh")); err == nil {
		return n
	}
	digit := func(value string) int {
		if value == "两" {
			return 2
		}
		if value == "零" {
			return 0
		}
		if utf8.RuneCountInString(value) != 1 {
			return -1
		}
		r, _ := utf8.DecodeRuneInString(value)
		index := strings.IndexRune("〇一二三四五六七八九", r)
		if index < 0 {
			return -1
		}
		return index / 3
	}
	if before, after, ok := strings.Cut(word, "十"); ok {
		tens, units := 1, 0
		if before != "" {
			tens = digit(before)
		}
		if after != "" {
			units = digit(after)
		}
		if tens < 0 || units < 0 {
			return 0
		}
		return tens*10 + units
	}
	if utf8.RuneCountInString(word) == 1 {
		return max(digit(word), 0)
	}
	return 0
}

var questionStopWords = strings.Fields("what which where how does do is are in of the that this its from can you explain summarize show tell paper article please give authors used use they formulas formula formulas equation equations figure fig a an for and about with")

func paperQuestionTerms(text string) []string {
	terms := make([]string, 0, 12)
	// Keep Chinese subject words together after removing common question phrases.
	text = strings.NewReplacer("里面", " ", "里的", " ", "论文里", " ", "文献里", " ", "的", " ", "是什么", " ", "是哪", " ", "公式", " ", "方程", " ", "这篇", " ", "该篇", " ", "论文", " ", "文献", " ", "文章", " ", "请", " ", "解释", " ", "说明", " ", "总结", " ").Replace(strings.ToLower(text))
	for _, term := range strings.FieldsFunc(text, func(r rune) bool { return !unicode.IsLetter(r) && !unicode.IsNumber(r) && r != '-' }) {
		if utf8.RuneCountInString(term) < 2 || slices.Contains(questionStopWords, term) || slices.Contains(terms, term) {
			continue
		}
		terms = append(terms, term)
		if len(terms) == 12 {
			break
		}
	}
	return terms
}

func (s *Service) SuggestPaperPassages(ctx context.Context, question PaperQuestion) ([]PaperPassage, error) {
	if utf8.RuneCountInString(question.Text) > 12000 || len(question.VisiblePaperIDs) > 20000 || len(question.Selected) > 4 {
		return nil, errors.New("论文问题或来源选择超出大小限制")
	}
	intent := parsePaperQuestion(question.Text)
	explicit := len(intent.ordinals) != 0 || len(intent.figures) != 0 || len(intent.equations) != 0 || intent.refersToPaper
	if !explicit && !intent.formula && intent.section == "" {
		return nil, nil
	}
	anchor := question.CurrentPaper
	if anchor == "" {
		for _, selected := range question.Selected {
			if selected.Kind != "paper" && selected.Kind != "paper-markdown" {
				continue
			}
			if anchor != "" && anchor != selected.ID {
				anchor = ""
				break
			}
			anchor = selected.ID
		}
	}
	if !explicit && anchor == "" && (!intent.formula || question.Project == "") {
		return nil, nil
	}
	if question.Project == "" {
		if explicit {
			return nil, errors.New("请进入对应项目并选择要查询的论文原文")
		}
		return nil, nil
	}
	if len(intent.ordinals) > 1 || len(intent.figures)+len(intent.equations) > 4 {
		return nil, errors.New("请一次查询一篇论文和至多四个图或公式编号")
	}
	if !s.HasActiveProject(question.Project) {
		return nil, ErrWorkflowSource
	}
	if err := s.WithProjectDirectory(question.Project, func(string) error { return nil }); err != nil {
		return nil, err
	}
	papers := filterPapers(s.papers.all(), question.Project, "", "")
	if len(intent.ordinals) == 1 {
		n := intent.ordinals[0]
		count := len(papers)
		if question.VisiblePaperIDs != nil {
			count = len(question.VisiblePaperIDs)
		}
		if n < 1 || n > count {
			return nil, fmt.Errorf("当前论文列表没有第 %d 篇，请检查列表顺序或选择原文", n)
		}
		if question.VisiblePaperIDs != nil {
			anchor = question.VisiblePaperIDs[n-1]
		} else {
			anchor = papers[n-1].ID
		}
	} else {
		var named string
		lower := strings.ToLower(question.Text)
		for _, paper := range papers {
			title := strings.TrimSpace(strings.ToLower(paper.Title))
			if utf8.RuneCountInString(title) < 5 || !strings.Contains(lower, title) {
				continue
			}
			if named != "" {
				return nil, errors.New("问题涉及多篇论文，请指定要查询的论文")
			}
			named = paper.ID
		}
		if named != "" {
			anchor = named
		}
	}
	if anchor == "" && !explicit {
		return nil, nil
	}
	if anchor == "" {
		return nil, errors.New("请指出对应项目中的论文标题或顺序，或选择一段论文原文")
	}
	i := slices.IndexFunc(papers, func(p Paper) bool { return p.ID == anchor })
	if i < 0 {
		return nil, ErrWorkflowSource
	}
	target := papers[i]
	matches := intent.selectors()
	needed := matches[:0]
	for _, match := range matches {
		if !slices.ContainsFunc(question.Selected, func(selection PaperQuestionSelection) bool {
			return selection.ID == target.ID && (selection.Kind == "paper" || selection.Kind == "paper-markdown") &&
				match.find(selection.Quote, "") != nil
		}) {
			needed = append(needed, match)
		}
	}
	if len(needed) == 0 {
		return nil, nil
	}
	for _, module := range []string{"ai-lab", "paper-library"} {
		enabled, err := s.ModuleEnabled(question.Project, module)
		if err != nil {
			return nil, err
		}
		if !enabled {
			return nil, fmt.Errorf("当前项目已停用模块 %s，请选择已授权的论文原文", module)
		}
	}
	raw, paper, err := s.workflowMarkdown(question.Project, target.ID)
	if err != nil {
		return nil, fmt.Errorf("无法读取《%s》的 Markdown 正文：%w。可以选择 PDF 原文或导入、转换后重试", target.Title, err)
	}
	body := normalizeWorkflowText(raw)
	input := strings.Split(body, "\n")
	lines := paperBodyLines(input)
	var passages []PaperPassage
	for _, match := range needed {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		chosen := match.choose(lines, input, intent.terms)
		if chosen == nil {
			return nil, fmt.Errorf("《%s》的正文中未定位到%s。请选择相应原文后重试", paper.Title, match.label())
		}
		passage := PaperPassage{
			SourceLocation: SourceLocation{Kind: "paper-markdown", ID: paper.ID, Offset: chosen.offset},
			Title:          paper.Title, Line: chosen.line, EndLine: chosen.line + strings.Count(chosen.quote, "\n"),
			Heading: chosen.heading, Hash: paper.Markdown.Hash, Quote: chosen.quote,
		}
		if !slices.ContainsFunc(passages, func(other PaperPassage) bool { return other.SourceLocation == passage.SourceLocation }) {
			passages = append(passages, passage)
		}
	}
	return passages, nil
}
