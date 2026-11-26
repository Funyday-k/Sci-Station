package meeting

// WithReviewSession keeps the recorded output, project and evidence unchanged
// until the host completes its atomic write. The callback must not reenter the
// meeting engine and never receives the ability to update the transcript.
func (e *Engine) WithReviewSession(id string, review func(*Session)) error {
	return e.locked(func() error {
		s, err := e.load(id)
		if err != nil {
			return err
		}
		if err = e.recover(s); err != nil {
			return err
		}
		review(s)
		return nil
	})
}
