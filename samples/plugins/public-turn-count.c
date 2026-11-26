#include <stddef.h>
#include <stdint.h>

enum {
    INPUT_LIMIT = 256 * 1024,
    OUTPUT_LIMIT = 128 * 1024,
    // Every distinct seat needs at least one turn object with a seat field.
    MAX_SEATS = INPUT_LIMIT / (sizeof("{\"seat\":\"\"}") - 1),
    SLOT_COUNT = 32768,
};

typedef struct {
    const char *start;
    const char *end;
} Span;

typedef struct {
    Span id;
    Span name;
    unsigned turns;
    unsigned slot;
} SeatCount;

static char input[INPUT_LIMIT];
static char output[OUTPUT_LIMIT];
static SeatCount seats[MAX_SEATS];
// Store seat indexes plus one; zero marks an empty slot.
static unsigned slots[SLOT_COUNT];

uint32_t alloc(uint32_t length) {
    return length <= sizeof(input) ? (uint32_t)(uintptr_t)input : 0;
}

static const char *skip_space(const char *p, const char *end) {
    while (p < end && (*p == ' ' || *p == '\n' || *p == '\r' || *p == '\t')) {
        ++p;
    }
    return p;
}

static const char *string_end(const char *p, const char *end) {
    for (++p; p < end; ++p) {
        if (*p == '"') {
            return p + 1;
        }
        if (*p == '\\' && p + 1 < end) {
            ++p;
        }
    }
    return end;
}

// The host encodes the input as valid JSON. Skip a complete value, including
// escaped strings in nested arrays and objects, without recursion or a heap.
static const char *value_end(const char *p, const char *end) {
    if (p == end) {
        return end;
    }
    if (*p == '"') {
        return string_end(p, end);
    }
    if (*p != '{' && *p != '[') {
        while (p < end && *p != ',' && *p != '}' && *p != ']' &&
               skip_space(p, end) == p) {
            ++p;
        }
        return p;
    }

    unsigned depth = 1;
    for (++p; p < end && depth != 0;) {
        switch (*p) {
        case '"':
            p = string_end(p, end);
            continue;
        case '{':
        case '[':
            ++depth;
            break;
        case '}':
        case ']':
            --depth;
            break;
        }
        ++p;
    }
    return p;
}

static size_t span_size(Span span) {
    return (size_t)(span.end - span.start);
}

static int same_span(Span a, Span b) {
    size_t length = span_size(a);
    if (length != span_size(b)) {
        return 0;
    }
    for (size_t i = 0; i < length; ++i) {
        if (a.start[i] != b.start[i]) {
            return 0;
        }
    }
    return 1;
}

static Span object_member(Span object, Span name) {
    const char *p = skip_space(object.start, object.end);
    if (p < object.end && *p == '{') {
        for (++p; p < object.end;) {
            p = skip_space(p, object.end);
            if (p == object.end || *p != '"') {
                break;
            }
            Span key = {p, string_end(p, object.end)};
            p = skip_space(key.end, object.end);
            if (p == object.end || *p != ':') {
                break;
            }
            const char *start = skip_space(p + 1, object.end);
            Span value = {start, value_end(start, object.end)};
            if (same_span(key, name)) {
                return value;
            }
            p = skip_space(value.end, object.end);
            if (p == object.end || *p != ',') {
                break;
            }
            ++p;
        }
    }
    return (Span){NULL, NULL};
}

static unsigned seat_slot(Span id) {
    uint32_t hash = UINT32_C(2166136261);
    for (const char *p = id.start; p < id.end; ++p) {
        hash = (hash ^ (unsigned char)*p) * UINT32_C(16777619);
    }
    unsigned slot = hash % SLOT_COUNT;
    while (slots[slot] != 0 && !same_span(seats[slots[slot] - 1].id, id)) {
        slot = (slot + 1) % SLOT_COUNT;
    }
    return slot;
}

static char *copy_bytes(char *dest, const char *source, size_t length) {
    for (size_t i = 0; i < length; ++i) {
        *dest++ = source[i];
    }
    return dest;
}

#define COPY_LITERAL(dest, literal) copy_bytes((dest), (literal), sizeof(literal) - 1)

static char *copy_unsigned(char *dest, unsigned value) {
    char digits[10];
    char *cursor = digits + sizeof(digits);
    do {
        *--cursor = (char)('0' + value % 10);
        value /= 10;
    } while (value != 0);
    return copy_bytes(dest, cursor, (size_t)(digits + sizeof(digits) - cursor));
}

static unsigned hex_digit(char c) {
    if (c >= '0' && c <= '9') return (unsigned)(c - '0');
    if (c >= 'a' && c <= 'f') return (unsigned)(c - 'a' + 10);
    if (c >= 'A' && c <= 'F') return (unsigned)(c - 'A' + 10);
    return 0;
}

static uint32_t escaped_codepoint(const char *p) {
    return (hex_digit(p[0]) << 12) | (hex_digit(p[1]) << 8) |
           (hex_digit(p[2]) << 4) | hex_digit(p[3]);
}

static char *copy_codepoint(char *dest, uint32_t codepoint) {
    if (codepoint <= 0x7f) {
        *dest++ = (char)codepoint;
    } else if (codepoint <= 0x7ff) {
        *dest++ = (char)(0xc0 | (codepoint >> 6));
        *dest++ = (char)(0x80 | (codepoint & 0x3f));
    } else if (codepoint <= 0xffff) {
        *dest++ = (char)(0xe0 | (codepoint >> 12));
        *dest++ = (char)(0x80 | ((codepoint >> 6) & 0x3f));
        *dest++ = (char)(0x80 | (codepoint & 0x3f));
    } else {
        *dest++ = (char)(0xf0 | (codepoint >> 18));
        *dest++ = (char)(0x80 | ((codepoint >> 12) & 0x3f));
        *dest++ = (char)(0x80 | ((codepoint >> 6) & 0x3f));
        *dest++ = (char)(0x80 | (codepoint & 0x3f));
    }
    return dest;
}

// Decode JSON escapes for display. Control characters remain visible as
// escapes so a seat name cannot inject extra lines into the result.
static char *copy_display_name(char *dest, Span encoded) {
    for (const char *p = encoded.start; p < encoded.end;) {
        if (*p != '\\') {
            *dest++ = *p++;
            continue;
        }
        char escape = *++p;
        ++p;
        switch (escape) {
        case '"': *dest++ = '"'; break;
        case '\\': *dest++ = '\\'; break;
        case '/': *dest++ = '/'; break;
        case 'b': *dest++ = '\\'; *dest++ = 'b'; break;
        case 'f': *dest++ = '\\'; *dest++ = 'f'; break;
        case 'n': *dest++ = '\\'; *dest++ = 'n'; break;
        case 'r': *dest++ = '\\'; *dest++ = 'r'; break;
        case 't': *dest++ = '\\'; *dest++ = 't'; break;
        case 'u': {
            uint32_t codepoint = escaped_codepoint(p);
            p += 4;
            if (codepoint >= 0xd800 && codepoint <= 0xdbff &&
                p + 6 <= encoded.end && p[0] == '\\' && p[1] == 'u') {
                uint32_t low = escaped_codepoint(p + 2);
                if (low >= 0xdc00 && low <= 0xdfff) {
                    codepoint = 0x10000 + ((codepoint - 0xd800) << 10) +
                                (low - 0xdc00);
                    p += 6;
                }
            }
            if (codepoint < 0x20 || (codepoint >= 0xd800 && codepoint <= 0xdfff)) {
                dest = COPY_LITERAL(dest, "\\u");
                dest = copy_bytes(dest, p - 4, 4);
            } else {
                dest = copy_codepoint(dest, codepoint);
            }
            break;
        }
        }
    }
    return dest;
}

static uint64_t result(char *end) {
    return ((uint64_t)(uintptr_t)output << 32) | (uint32_t)(end - output);
}

uint64_t run(uint32_t ptr, uint32_t length) {
    if (ptr != (uint32_t)(uintptr_t)input || length > sizeof(input)) {
        return result(COPY_LITERAL(output, "输入无效。\n"));
    }
    static const char turns_key[] = "\"turns\"";
    static const char seat_key[] = "\"seat\"";
    static const char seat_name_key[] = "\"seat_name\"";
    Span turns = object_member((Span){input, input + length},
                               (Span){turns_key, turns_key + sizeof(turns_key) - 1});
    if (turns.start == NULL || turns.start == turns.end) {
        return result(COPY_LITERAL(output, "缺少公开发言数据。\n"));
    }

    unsigned total = 0;
    unsigned seat_count = 0;
    if (*turns.start == '[') {
        for (const char *p = skip_space(turns.start + 1, turns.end);
             p < turns.end && *p == '{';) {
            Span turn = {p, value_end(p, turns.end)};
            Span seat = object_member(turn, (Span){seat_key, seat_key + sizeof(seat_key) - 1});
            Span seat_name = object_member(turn,
                (Span){seat_name_key, seat_name_key + sizeof(seat_name_key) - 1});
            ++total;
            if (seat.start != NULL && seat.end - seat.start > 2 && *seat.start == '"') {
                // Host seat IDs are stable ASCII identifiers. Compare their JSON
                // contents byte-for-byte and preserve first-appearance order.
                Span id = {seat.start + 1, seat.end - 1};
                unsigned slot = seat_slot(id);
                if (slots[slot] == 0) {
                    Span name = {NULL, NULL};
                    if (seat_name.start != NULL && seat_name.end - seat_name.start > 2 &&
                        *seat_name.start == '"') {
                        name = (Span){seat_name.start + 1, seat_name.end - 1};
                    }
                    seats[seat_count] = (SeatCount){id, name, 0, slot};
                    slots[slot] = ++seat_count;
                } else if (seats[slots[slot] - 1].name.start == NULL &&
                           seat_name.start != NULL && seat_name.end - seat_name.start > 2 &&
                           *seat_name.start == '"') {
                    seats[slots[slot] - 1].name =
                        (Span){seat_name.start + 1, seat_name.end - 1};
                }
                ++seats[slots[slot] - 1].turns;
            }
            p = skip_space(turn.end, turns.end);
            if (p == turns.end || *p != ',') {
                break;
            }
            p = skip_space(p + 1, turns.end);
        }
    }

    char *end = COPY_LITERAL(output, "公开发言：");
    end = copy_unsigned(end, total);
    end = COPY_LITERAL(end, " 条\n有发言的席位：");
    end = copy_unsigned(end, seat_count);
    end = COPY_LITERAL(end, " 个\n");
    if (seat_count > 0) {
        end = COPY_LITERAL(end, "\n各席位发言次数\n");
    }

    static const char omitted[] = "其余席位的明细因输出长度限制省略。\n";
    int truncated = 0;
    for (unsigned i = 0; i < seat_count; ++i) {
        SeatCount seat = seats[i];
        slots[seat.slot] = 0;
        size_t id_length = span_size(seat.id);
        size_t name_length = seat.name.start == NULL ? 0 : span_size(seat.name);
        size_t remaining = sizeof(output) - (size_t)(end - output);
        if (truncated || remaining < id_length + name_length + 40 + sizeof(omitted)) {
            truncated = 1;
            continue;
        }
        end = COPY_LITERAL(end, "- ");
        if (seat.name.start != NULL) {
            end = copy_display_name(end, seat.name);
            end = COPY_LITERAL(end, " [");
            end = copy_bytes(end, seat.id.start, id_length);
            end = COPY_LITERAL(end, "]");
        } else {
            end = copy_bytes(end, seat.id.start, id_length);
        }
        end = COPY_LITERAL(end, "：");
        end = copy_unsigned(end, seat.turns);
        end = COPY_LITERAL(end, " 条\n");
    }
    if (truncated) {
        end = COPY_LITERAL(end, omitted);
    }
    return result(end);
}
