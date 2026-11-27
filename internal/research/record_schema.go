package research

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
)

const researchRecordSchemaVersion = 1

// The version belongs to the on-disk record, separate from API revisions.
type projectRecord struct {
	SchemaVersion int `json:"schema_version"`
	projectData
}

type paperRecord struct {
	SchemaVersion int `json:"schema_version"`
	Paper
}

func decodeResearchRecord(data []byte, out any) error {
	decoder := json.NewDecoder(bytes.NewReader(data))
	start, err := decoder.Token()
	if err != nil || start != json.Delim('{') {
		return errors.New("记录必须为 JSON 对象")
	}
	var value json.RawMessage
	hasVersion := false
	for decoder.More() {
		key, err := decoder.Token()
		if err != nil {
			return err
		}
		if err := decoder.Decode(&value); err != nil {
			return err
		}
		if key != "schema_version" {
			continue
		}
		var version *int
		if hasVersion || json.Unmarshal(value, &version) != nil || version == nil {
			return errors.New("无效的 schema_version")
		}
		if *version != researchRecordSchemaVersion {
			return fmt.Errorf("不支持的 schema_version %d", *version)
		}
		hasVersion = true
	}
	// The typed decode also checks the complete object and its domain fields.
	return json.Unmarshal(data, out)
}
