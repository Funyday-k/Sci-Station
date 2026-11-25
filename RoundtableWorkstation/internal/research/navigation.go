package research

// HasWorkspacePaper resolves a reader link against the active library and,
// when present, the requested project membership.
func (s *Service) HasWorkspacePaper(id, project string) bool {
	paper, ok := s.papers.Snapshot(id)
	return ok && (project == "" || paperContains(paper.ProjectIDs, project))
}
