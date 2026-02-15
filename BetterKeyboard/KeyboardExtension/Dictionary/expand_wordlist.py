#!/usr/bin/env python3
"""
Expand the keyboard dictionary to ~50k words.

Strategy:
1. Keep existing 10k words in their current order (positions 0-9999)
2. Download a 50k frequency-ordered word list (from OpenSubtitles corpus)
3. Load macOS system dictionary (/usr/share/dict/words) as a validation set
4. For NEW words (not in existing 10k), require they exist in the system dictionary
   — this filters out proper nouns, character names, and subtitle junk
5. Generate common inflected forms of known words (validated against sys dict)
6. Supplement with system dictionary words ranked by usefulness
7. Fill to ~50k, with heavy quality filtering on supplemental words

The system dictionary cross-reference is the key insight: the frequency list
has great ordering but includes names/junk. The system dict has clean English
words but no frequency data. Intersecting them gives us frequency-ordered
real English words.

For the supplement phase, we aggressively filter out obscure/archaic words
using root-word validation, suspicious prefix/suffix detection, and length
heuristics. Better to have 48k good words than 50k with garbage at the tail.
"""

import re
import urllib.request
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
WORDS_FILE = os.path.join(SCRIPT_DIR, 'words.txt')
OUTPUT_FILE = os.path.join(SCRIPT_DIR, 'words.txt')  # Overwrite in place
TARGET_COUNT = 50000

# Words to explicitly exclude — profanity, slang, contraction fragments,
# archaic forms, and words that are technically in the system dict but
# shouldn't be in a modern keyboard dictionary.
EXCLUDE_WORDS = {
    # Single letters (keep 'i' and 'a')
    'b', 'c', 'd', 'e', 'f', 'g', 'h', 'j', 'k', 'l', 'm', 'n', 'o', 'p',
    'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',

    # Abbreviations / not real words
    'hr', 'fa', 'md', 'vs', 'ok', 'ad', 'id', 'tv', 'uk', 'eu',
    'bc', 'dc', 'dj', 'gp', 'pc', 'pm', 'am', 'ph', 'em',
    'um', 'uh', 'hm', 'mm', 'ah', 'oh', 'ha', 'ho', 'hi', 'huh',
    'aw', 'ow', 'oy', 'ay', 'eh', 'sh', 'ya', 'yo', 'na', 'la',
    'da', 'ma', 'pa', 'oi', 'oo', 'ew', 'shh', 'hmm', 'uhh', 'umm',
    'ahh', 'ohh', 'aww', 'ooh', 'heh', 'whoa', 'woah', 'nah', 'yah',
    'yeah', 'yep', 'nope', 'yup', 'ugh', 'mhm', 'mmm', 'mmhmm',
    'psst', 'shoo', 'boo', 'hah', 'tsk', 'brr', 'grr', 'argh',
    'blah', 'duh', 'tut', 'whew', 'phew', 'jeez', 'geez', 'gee',

    # Contraction fragments (from "'t", "'s", "'d" etc in subtitles)
    'didn', 'doesn', 'isn', 'wasn', 'wouldn', 'couldn', 'shouldn',
    'hadn', 'hasn', 'aren', 'weren', 'won', 'ain', 'don', 'haven',
    'mustn', 'needn', 'shan', 'll', 've', 're',

    # Profanity / vulgar
    'shit', 'shitty', 'shitting', 'fuck', 'fucking', 'fucked', 'fucker',
    'damn', 'damned', 'dammit', 'goddamn', 'goddamned',
    'ass', 'asses', 'asshole', 'assholes',
    'bitch', 'bitches', 'bitching',
    'bastard', 'bastards',
    'crap', 'crappy', 'crapping',
    'piss', 'pissed', 'pissing',
    'dick', 'dicks',
    'cock', 'cocks',
    'pussy', 'pussies',
    'slut', 'sluts', 'slutty',
    'whore', 'whores',
    'nigger', 'niggers', 'nigga', 'niggas',
    'faggot', 'faggots', 'fag', 'fags',
    'retard', 'retarded', 'retards',
    'wank', 'wanker', 'wankers', 'wanking',
    'bollocks', 'bullshit', 'horseshit',
    'tits', 'titty', 'titties', 'boobs', 'boobies',
    'cunt', 'cunts',
    'twat', 'twats',
    'arse', 'arses', 'arsehole',
    'boner', 'boners',
    'dildo', 'dildos',
    'douche', 'douchebag',
    'jackass',
    'motherfucker', 'motherfuckers', 'motherfucking',

    # Internet slang / informal contractions
    'lol', 'omg', 'wtf', 'idk', 'imo', 'tbh', 'smh', 'af', 'btw',
    'gonna', 'gotta', 'wanna', 'dunno', 'lemme', 'kinda', 'sorta',
    'coulda', 'woulda', 'shoulda', 'oughta', 'hafta', 'outta',
    'gotcha', 'whatcha', 'betcha',

    # Common subtitle artifacts / foreign words
    'le', 'de', 'el', 'di', 'en', 'du', 'et', 'un',
    'ta', 'tu',

    # Archaic / obsolete forms people won't type on a phone
    'wouldst', 'shouldst', 'couldst', 'dost', 'doth', 'hast', 'hath',
    'shalt', 'wilt', 'thou', 'thee', 'thy', 'thine', 'ye', 'art',
    'wherefore', 'whence', 'thence', 'hither', 'thither', 'hitherto',
    'forsooth', 'prithee', 'perchance', 'methinks', 'betwixt', 'amongst',
    'whilst', 'unto', 'ere', 'oft', 'nay', 'aye', 'begone', 'alas',
    'hark', 'verily', 'nought', 'naught', 'twain', 'yonder', 'hence',
    'woe', 'beseech', 'behold', 'hearken', 'brethren', 'damsel',
    'maiden', 'cometh', 'saith', 'sayeth', 'maketh', 'giveth',
    'taketh', 'goeth', 'knoweth', 'loveth',

    # Subtitle artifacts — proper nouns that sneak through lowercase
    'streep', 'claude', 'whoo', 'dag', 'mala',
}

# Words to explicitly INCLUDE even if they fail some filter.
# These are words real humans type on their phones.
FORCE_INCLUDE = {
    # Adverbs — long-form adverbs are the #1 gap in frequency lists
    'intuitively', 'definitively', 'comprehensively', 'simultaneously',
    'approximately', 'unfortunately', 'alternatively', 'enthusiastically',
    'immediately', 'particularly', 'significantly', 'independently',
    'automatically', 'traditionally', 'professionally', 'fundamentally',
    'extraordinarily', 'predominantly', 'consistently', 'continuously',
    'subsequently', 'substantially', 'overwhelmingly', 'retrospectively',
    'strategically', 'systematically', 'hypothetically', 'theoretically',
    'philosophically', 'psychologically', 'technologically', 'economically',
    'environmentally', 'internationally', 'experimentally', 'constitutionally',
    'unconditionally', 'unquestionably', 'unequivocally', 'categorically',
    'proportionally', 'provisionally', 'exceptionally',
    'occasionally', 'coincidentally', 'incidentally',
    'accidentally', 'intentionally', 'conventionally',
    'paradoxically', 'metaphorically', 'symbolically', 'grammatically',
    'alphabetically', 'chronologically', 'geographically',
    'statistically', 'mathematically', 'scientifically', 'politically',
    'diplomatically', 'democratically', 'pragmatically',
    'emphatically', 'authentically', 'optimistically', 'pessimistically',
    'realistically',
    'instinctively', 'constructively', 'destructively', 'effectively',
    'collectively', 'respectively', 'prospectively', 'selectively',
    'exclusively', 'inclusively', 'extensively', 'intensively',
    'accordingly', 'additionally', 'admittedly', 'aggressively',
    'analytically', 'appropriately', 'characteristically', 'comparatively',
    'competitively', 'comprehensibly', 'conceptually', 'conclusively',
    'conditionally', 'confidentially', 'consciously', 'conservatively',
    'considerably', 'conspicuously', 'contextually', 'convincingly',
    'cooperatively', 'correspondingly', 'courageously', 'creatively',
    'critically', 'decisively', 'defensively', 'deliberately',
    'demonstrably', 'desperately', 'disproportionately', 'distinctively',
    'dramatically', 'electronically', 'emotionally', 'energetically',
    'exponentially', 'extraordinarily', 'figuratively', 'financially',
    'forcefully', 'fortunately', 'functionally', 'generously',
    'genuinely', 'gracefully', 'imaginatively', 'impressively',
    'inadequately', 'increasingly', 'indefinitely', 'individually',
    'inevitably', 'informally', 'inherently', 'innovatively',
    'instinctively', 'intellectually', 'interchangeably', 'internally',
    'involuntarily', 'ironically', 'irreversibly', 'legitimately',
    'marginally', 'meaningfully', 'mechanically', 'methodically',
    'miraculously', 'moderately', 'momentarily', 'mysteriously',
    'naturally', 'negatively', 'noticeably', 'objectively',
    'offensively', 'operationally', 'organically', 'passionately',
    'periodically', 'permanently', 'personally', 'persuasively',
    'phenomenally', 'physically', 'positively', 'practically',
    'predictably', 'preferably', 'presumably', 'previously',
    'primarily', 'principally', 'privately', 'productively',
    'profoundly', 'progressively', 'prominently', 'proportionately',
    'provisionally', 'psychologically', 'purposefully', 'reasonably',
    'reflexively', 'regrettably', 'reluctantly', 'remarkably',
    'repeatedly', 'reportedly', 'representatively', 'responsibly',
    'rhetorically', 'rigorously', 'ruthlessly', 'satisfactorily',
    'seemingly', 'separately', 'simultaneously', 'sincerely',
    'skeptically', 'specifically', 'spectacularly', 'spontaneously',
    'structurally', 'subjectively', 'successfully', 'sufficiently',
    'superficially', 'surprisingly', 'symbolically', 'sympathetically',
    'temporarily', 'tentatively', 'therapeutically', 'thoroughly',
    'thoughtfully', 'transparently', 'tremendously', 'typically',
    'unanimously', 'unconditionally', 'understandably', 'undoubtedly',
    'unexpectedly', 'unfortunately', 'universally', 'unnecessarily',
    'unreasonably', 'voluntarily', 'wholeheartedly',

    # Important adjectives / nouns
    'comprehensible', 'incomprehensible', 'indispensable', 'knowledgeable',
    'interchangeable', 'distinguishable',
    'uncomfortable', 'unreasonable', 'unsustainable', 'unprecedented',
    'quintessential', 'interdisciplinary',
    'complementary', 'supplementary', 'parliamentary', 'evolutionary',
    'revolutionary', 'counterproductive', 'straightforward', 'nevertheless',
    'notwithstanding', 'undergraduate', 'entrepreneurial', 'infrastructure',
    'accountability', 'acknowledgement', 'advertisement', 'circumstances',
    'communication', 'comprehensive', 'concentration', 'configuration',
    'consciousness', 'consideration', 'constellation', 'controversial',
    'correspondence', 'determination', 'disappointment', 'documentation',
    'electromagnetic', 'encouragement', 'entertainment', 'establishment',
    'extraordinary', 'implementation', 'inappropriate', 'incorporation',
    'independently', 'infrastructure', 'interpretation', 'investigation',
    'manufacturing', 'mediterranean', 'miscellaneous', 'misunderstanding',
    'neighborhood', 'opportunities', 'organizational', 'pharmaceutical',
    'predominantly', 'questionnaire', 'recommendation', 'rehabilitation',
    'representative', 'responsibility', 'semiconductor', 'sophisticated',
    'sustainability', 'transformation', 'understanding', 'vulnerability',

    # Common tech/modern words that might not be in older dictionaries
    'smartphone', 'screenshot', 'download', 'upload', 'website',
    'database', 'software', 'hardware', 'internet', 'online',
    'offline', 'username', 'password', 'feedback', 'workflow',
    'startup', 'podcast', 'livestream', 'update', 'upgrade',
    'touchscreen', 'bluetooth', 'wifi',
}

# Prefixes that are strong indicators of obscure/technical/archaic words
# in the system dictionary. Words starting with these (especially when
# combined with other signals) should be scored lower.
OBSCURE_PREFIXES = {
    'ante', 'alti', 'alveol', 'angio', 'antero', 'arthro',
    'basi', 'brachi', 'bronch',
    'cardi', 'cephal', 'cerebr', 'cervic', 'chondr', 'crani',
    'derm', 'dors',
    'ecto', 'endo', 'entero', 'epi',
    'fibro',
    'gastr', 'gingiv', 'gloss',
    'hemo', 'hepat', 'histo', 'hypo', 'hyper',
    'infra', 'intra', 'irid',
    'laryng', 'lingu', 'lymph',
    'mast', 'mening', 'myc', 'myel',
    'naso', 'nephr', 'neur',
    'oculo', 'olfact', 'ophthalm', 'osteo', 'oto',
    'palat', 'pancreat', 'pector', 'periton', 'pharyng', 'phren',
    'pleur', 'pneum', 'prostat', 'pulmon', 'pylor',
    'rhin',
    'scler', 'splanchn', 'spondyl', 'staphyl', 'stern', 'strept',
    'synov',
    'thorac', 'thromb', 'thyr', 'trache', 'tympan',
    'uret', 'uterin', 'uvul',
    'vascul', 'vesicul', 'viscer',
}

# Suffixes that are strong indicators of obscure/technical words
OBSCURE_SUFFIXES = {
    'aceous', 'acious', 'atory', 'atorial',
    'escent', 'iform', 'itious', 'ulous',
    'aceous', 'iferous', 'igenous', 'iguous',
    'ivorous', 'ological',
}


def is_valid_word(word):
    """Basic validity check for a word."""
    if not word:
        return False
    if not re.match(r'^[a-z]+$', word):
        return False
    if len(word) < 2 and word not in ('i', 'a'):
        return False
    if len(word) > 22:
        return False
    if word in EXCLUDE_WORDS:
        return False
    return True


def is_likely_obscure(word):
    """
    Heuristic check for words that are technically in the system dictionary
    but are obscure, archaic, or overly technical. Returns True if the word
    seems obscure and should be penalized or excluded from supplemental lists.

    This is NOT applied to frequency-list words (they proved their frequency).
    Only used when pulling supplemental words from the system dictionary.
    """
    # Very long words without a known root are probably obscure
    if len(word) > 14:
        return True

    # Check for obscure medical/scientific prefixes
    for prefix in OBSCURE_PREFIXES:
        if word.startswith(prefix) and len(word) > len(prefix) + 3:
            return True

    # Check for obscure suffixes
    for suffix in OBSCURE_SUFFIXES:
        if word.endswith(suffix):
            return True

    # Double consonant clusters that suggest Latin/Greek origin technical terms
    if re.search(r'(?:ph|th|ch)(?:ph|th|ch)', word):
        return True

    # Words ending in archaic patterns
    archaic_endings = ('eth', 'est', 'ith', 'ism')  # keepeth, greatest is ok but we check context
    # Only flag -eth/-est if they look archaic (not like "growth", "greatest")
    if word.endswith('eth') and len(word) > 5 and not word.endswith('reth'):
        return True
    if word.endswith('ism') and len(word) > 10:
        # Long -ism words are usually obscure (e.g., "boosterism", "borderism")
        return True

    return False


def load_existing_words():
    """Load the current word list, but only keep the FIRST 10k (the original
    frequency-ordered core). Everything after that was from the previous
    expansion attempt and will be rebuilt."""
    with open(WORDS_FILE, 'r') as f:
        words = [line.strip().lower() for line in f if line.strip()]

    # Only keep the original 10k — the rest was from the broken expansion
    original_count = len(words)
    words = words[:10000]
    print(f"Loaded {original_count} words, keeping first {len(words)} (original core)")
    return words


def download_frequency_list():
    """Download the 50k frequency word list from OpenSubtitles corpus."""
    url = 'https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/en/en_50k.txt'
    print(f"Downloading frequency list...")
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    resp = urllib.request.urlopen(req, timeout=30)
    data = resp.read().decode('utf-8')

    words_with_freq = []
    for line in data.strip().split('\n'):
        parts = line.strip().split()
        if len(parts) >= 2:
            word = parts[0].lower()
            try:
                freq = int(parts[1])
            except ValueError:
                continue
            if is_valid_word(word):
                words_with_freq.append((word, freq))

    print(f"  Got {len(words_with_freq)} valid words from frequency list")
    return words_with_freq


def load_system_dictionary():
    """
    Load macOS system dictionary as a SET for validation.
    Only words that appear in LOWERCASE form in the dict file are included.
    Words that only appear capitalized (proper nouns) are excluded.
    """
    dict_path = '/usr/share/dict/words'
    if not os.path.exists(dict_path):
        print("WARNING: No system dictionary found at /usr/share/dict/words")
        return set()

    lowercase_words = set()
    capitalized_only = set()

    with open(dict_path, 'r') as f:
        for line in f:
            word = line.strip()
            if not word:
                continue
            if re.match(r'^[a-z]+$', word):
                lowercase_words.add(word)
            elif re.match(r'^[A-Z][a-z]+$', word):
                lower = word.lower()
                if lower not in lowercase_words:
                    capitalized_only.add(lower)

    print(f"  System dict: {len(lowercase_words)} lowercase words, "
          f"{len(capitalized_only)} capitalized-only (likely proper nouns)")

    return lowercase_words


def generate_inflections(base_words, sys_dict, high_priority_bases=None):
    """
    Generate common inflected forms of existing words, validated against
    the system dictionary. Returns list of (word, priority_score) tuples.

    This fills the gap where the frequency list doesn't have a word form
    but it's a perfectly valid inflection of a common word.

    Quality control: we're conservative here. The system dictionary validates
    tons of obscure words (e.g., "speechment", "spiritize", "societyless").
    We limit generated word length, restrict which suffixes apply to which
    base lengths, and skip results that look obscure.

    Args:
        base_words: set of base words to generate inflections from
        sys_dict: system dictionary set for validation
        high_priority_bases: optional set of words from the first 10k
            (these get a priority boost for their inflections)
    """
    if high_priority_bases is None:
        high_priority_bases = set()

    # Core inflection rules — the most productive, common English patterns.
    # These are the inflections people ACTUALLY type on phones.
    # (suffix_to_add, letters_to_remove_first, min_base_len, max_result_len)
    suffix_rules = [
        # --- HIGH YIELD: basic verb/noun inflections ---
        ('s', '', 2, 14),
        ('es', '', 2, 14),
        ('ies', 'y', 2, 14),      # baby -> babies
        ('ed', '', 3, 14),
        ('ed', 'e', 3, 14),       # bake -> baked
        ('ing', '', 3, 14),
        ('ing', 'e', 3, 14),      # make -> making
        ('er', '', 3, 13),
        ('er', 'e', 3, 13),
        ('ers', '', 3, 13),
        ('est', '', 3, 13),

        # --- MEDIUM YIELD: common derivational suffixes ---
        ('ly', '', 3, 15),        # Allow longer for adverbs (importantly, etc)
        ('ily', 'y', 3, 15),      # happy -> happily
        ('ness', '', 4, 13),      # Min base 4 to avoid "oddness" etc
        ('iness', 'y', 4, 13),    # happy -> happiness
        ('ment', '', 4, 13),
        ('ment', 'e', 4, 13),
        ('ments', '', 4, 13),
        ('tion', '', 4, 13),
        ('ation', 'e', 4, 13),
        ('tions', '', 4, 13),
        ('sion', '', 4, 13),
        ('ful', '', 4, 11),       # Tighter — avoids "gloomful", "pressful"
        ('less', '', 4, 11),      # Tighter — avoids "glareless", "glossless"
        ('able', '', 4, 12),
        ('able', 'e', 4, 12),
        ('ible', '', 4, 12),
        ('ive', '', 4, 11),
        ('ive', 'e', 4, 11),
        ('ous', '', 4, 11),       # Tighter — avoids "glareous"
        ('al', '', 4, 11),
        ('ally', '', 4, 13),
        ('ity', '', 4, 11),

        # --- LOWER YIELD: less common but still useful ---
        ('ize', '', 3, 12),
        ('ized', '', 3, 12),
        ('izing', '', 3, 13),
        ('ism', '', 3, 10),       # Shorter limit — long -ism words are obscure
        ('ist', '', 3, 10),
        ('ence', '', 3, 12),
        ('ance', '', 3, 12),
    ]

    # Prefix rules — VERY conservative.
    # The system dictionary has THOUSANDS of obscure un-/re-/pre- words
    # (e.g., "unbrooch", "preradio", "remication"). Most are useless.
    # Only generate prefixed forms of SHORT, HIGH-FREQUENCY bases.
    # (prefix, min_base_len, max_base_len, max_result_len)
    prefix_rules = [
        ('un', 3, 7, 10),       # unhappy, unclear, unfair
        ('re', 3, 6, 9),        # rebuild, rewrite, reopen
        ('dis', 3, 6, 10),      # disagree, dislike
        ('mis', 3, 6, 9),       # mislead, misread
        ('over', 3, 5, 10),     # overload, overlook
        ('out', 3, 5, 8),       # outrun, outplay
    ]

    generated = {}  # word -> priority_score

    base_set = set(base_words)  # For fast lookup

    for base in base_words:
        # Determine priority: words from the original 10k get lower scores
        # (= higher priority) since they're more common
        base_priority = len(base)
        if base in high_priority_bases:
            base_priority = max(1, base_priority - 2)  # Boost

        # Suffix rules
        for suffix, remove, min_len, max_len in suffix_rules:
            if len(base) < min_len:
                continue
            if remove and base.endswith(remove):
                candidate = base[:-len(remove)] + suffix
            elif not remove:
                candidate = base + suffix
            else:
                continue

            # Length cap — prevents obscure long derivations
            if len(candidate) > max_len:
                continue

            # Validate: must be in system dictionary and pass our filters
            if (candidate in sys_dict and
                    is_valid_word(candidate) and
                    candidate not in base_set):
                if candidate not in generated or generated[candidate] > base_priority:
                    generated[candidate] = base_priority

        # Prefix rules — ONLY for high-priority (original 10k) bases.
        # This prevents generating "preradio", "unbrooch", "remication" etc.
        # from words that were themselves added by frequency list or inflection.
        if base in high_priority_bases:
            for prefix, min_len, max_base_len, max_len in prefix_rules:
                if len(base) < min_len or len(base) > max_base_len:
                    continue
                candidate = prefix + base
                if len(candidate) > max_len:
                    continue
                if (candidate in sys_dict and
                        is_valid_word(candidate) and
                        candidate not in base_set):
                    if candidate not in generated or generated[candidate] > base_priority:
                        generated[candidate] = base_priority

    # Sort by priority (shorter base / higher-frequency base = higher priority)
    result = sorted(generated.items(), key=lambda x: (x[1], x[0]))
    return result


def score_supplement_word(word, included_set, sys_dict, word_rank=None):
    """
    Score a system dictionary word for usefulness as a supplemental addition.
    Higher score = more useful. Returns 0 or negative for words to skip.

    Key principle: a word is useful if a real person would actually type it
    on their phone. We heavily reward words whose ROOT is already in our set,
    with bonus points proportional to how common that root is.

    Args:
        word: the candidate word
        included_set: set of already-included words
        sys_dict: system dictionary set
        word_rank: optional dict of word -> rank (position in our list),
            used to give higher scores to derivations of common words
    """
    if word_rank is None:
        word_rank = {}

    score = 0

    # Hard reject obscure words
    if is_likely_obscure(word):
        return -10

    # === ROOT DETECTION ===
    # The most powerful signal: does this word's root already exist in our set?
    # If "manage" is in our list, "manageable" is obviously useful.
    has_known_root = False

    # Common suffixes and how to extract the root
    root_patterns = [
        # (suffix, root_transformations)
        # Each transformation: (chars_to_remove_from_end, chars_to_add)
        ('ingly', [('ingly', ''), ('ingly', 'e')]),
        ('ingly', [('ingly', ''), ('ingly', 'e'), ('ingly', 'ing')]),
        ('ously', [('ously', ''), ('ously', 'ous'), ('ously', 'e')]),
        ('ively', [('ively', ''), ('ively', 'ive'), ('ively', 'e')]),
        ('ately', [('ately', ''), ('ately', 'ate'), ('ately', 'e')]),
        ('lessly', [('lessly', ''), ('lessly', 'less')]),
        ('fully', [('fully', ''), ('fully', 'ful')]),
        ('ably', [('ably', ''), ('ably', 'able'), ('ably', 'e')]),
        ('ibly', [('ibly', ''), ('ibly', 'ible')]),
        ('tion', [('tion', ''), ('tion', 't'), ('ation', 'e'), ('ation', '')]),
        ('sion', [('sion', ''), ('sion', 'se'), ('sion', 'd'), ('sion', 'de')]),
        ('ment', [('ment', ''), ('ment', 'e')]),
        ('ness', [('ness', ''), ('iness', 'y')]),
        ('able', [('able', ''), ('able', 'e')]),
        ('ible', [('ible', ''), ('ible', 'e')]),
        ('ful', [('ful', '')]),
        ('less', [('less', '')]),
        ('ous', [('ous', ''), ('ious', 'y'), ('eous', 'e'), ('ous', 'e')]),
        ('ive', [('ive', ''), ('ive', 'e'), ('ative', 'e'), ('ative', '')]),
        ('ing', [('ing', ''), ('ing', 'e')]),
        ('tion', [('tion', 't'), ('tion', 'te')]),
        ('ed', [('ed', ''), ('ed', 'e'), ('ied', 'y')]),
        ('er', [('er', ''), ('er', 'e'), ('ier', 'y')]),
        ('est', [('est', ''), ('est', 'e'), ('iest', 'y')]),
        ('ly', [('ly', ''), ('ily', 'y'), ('ly', 'le')]),
        ('al', [('al', ''), ('al', 'e')]),
        ('ize', [('ize', ''), ('ize', 'e')]),
        ('ized', [('ized', ''), ('ized', 'e')]),
        ('izing', [('izing', ''), ('izing', 'e')]),
        ('ist', [('ist', '')]),
        ('ism', [('ism', '')]),
        ('ity', [('ity', ''), ('ity', 'e'), ('ility', 'le'), ('ibility', 'ible'), ('ability', 'able')]),
        ('ence', [('ence', ''), ('ence', 'e'), ('ence', 'ent')]),
        ('ance', [('ance', ''), ('ance', 'e'), ('ance', 'ant')]),
        ('s', [('s', ''), ('es', ''), ('ies', 'y')]),
    ]

    best_root_rank = 999999  # Track the best (lowest) rank of any matching root
    for suffix, transforms in root_patterns:
        if not word.endswith(suffix):
            continue
        for remove_suffix, add_back in transforms:
            if not word.endswith(remove_suffix):
                continue
            root = word[:-len(remove_suffix)] + add_back if remove_suffix else word
            if len(root) >= 3 and root in included_set:
                has_known_root = True
                root_rank = word_rank.get(root, 50000)
                best_root_rank = min(best_root_rank, root_rank)
                break
        if has_known_root:
            break

    if has_known_root:
        # Graduated bonus based on how common the root is.
        # Top-1000 root: +12 bonus (very common base word)
        # Top-5000 root: +8 bonus
        # Top-10000 root: +6 bonus
        # Beyond 10k: +3 bonus (root was itself supplemental)
        if best_root_rank < 1000:
            score += 12
        elif best_root_rank < 5000:
            score += 8
        elif best_root_rank < 10000:
            score += 6
        else:
            score += 3

    # Also check un-/re-/dis- prefix removal.
    # Prefix-only derivations are scored LOWER than suffix derivations,
    # because the system dictionary has thousands of obscure un-/re- words.
    if not has_known_root:
        for prefix in ('un', 're', 'dis', 'mis', 'pre', 'over', 'under', 'out', 'non'):
            if word.startswith(prefix) and len(word) > len(prefix) + 2:
                stem = word[len(prefix):]
                if stem in included_set:
                    has_known_root = True
                    stem_rank = word_rank.get(stem, 50000)
                    # Check if the word also ends with a common suffix
                    has_good_suffix = False
                    for suf in ('ing', 'ed', 'ly', 'er', 'est', 'ness', 'ment',
                                'tion', 'able', 'ible', 'ful', 'less', 'ive',
                                'ous', 'al', 'ity', 'ize'):
                        if stem.endswith(suf):
                            has_good_suffix = True
                            break
                    if has_good_suffix and stem_rank < 5000:
                        score += 7  # Good: "unbreakable", "mismanaged"
                    elif len(word) <= 9 and stem_rank < 3000:
                        score += 5  # OK: "unfair", "rebuild"
                    elif stem_rank < 2000:
                        score += 3  # Marginal: only if root is very common
                    else:
                        score += 0  # Skip: "unmonkly", "outsuffer" etc
                    break

    # === SUFFIX QUALITY ===
    # Words with common, productive English suffixes are more likely to be real
    useful_suffixes = {
        'ing': 3, 'tion': 3, 'sion': 3, 'ment': 3,
        'ness': 3, 'able': 3, 'ible': 3, 'ful': 3,
        'less': 3, 'ous': 3, 'ive': 3,
        'ally': 3, 'ized': 3, 'izing': 3,
        'ated': 3, 'ating': 3, 'ened': 3, 'ening': 3,
        'tion': 3, 'sion': 3,
        'ly': 2, 'er': 2, 'ed': 2, 'es': 2,
        'ism': 2, 'ist': 2, 'ity': 2, 'ure': 2,
        'ery': 2, 'ory': 2, 'ary': 2,
        'ence': 2, 'ance': 2, 'ency': 2, 'ancy': 2,
    }

    for suffix, points in useful_suffixes.items():
        if word.endswith(suffix) and len(word) > len(suffix) + 2:
            score += points
            break  # Only count best suffix match

    # === LENGTH SWEET SPOT ===
    # Medium-length words are what people actually type
    if 5 <= len(word) <= 10:
        score += 3
    elif 4 <= len(word) <= 12:
        score += 1
    elif len(word) <= 3:
        score -= 3
    elif len(word) > 14:
        score -= 3

    # === COMPOUND WORD DETECTION ===
    # If both halves of a compound are known, it's probably useful
    # e.g., "bookshelf" = "book" + "shelf"
    if not has_known_root and len(word) >= 6:
        for split in range(3, len(word) - 2):
            left = word[:split]
            right = word[split:]
            if left in included_set and right in included_set and len(right) >= 3:
                score += 6
                break

    # === COMMONALITY HEURISTICS ===
    # Penalize words that LOOK obscure even if they have known roots.
    # These patterns indicate technical/archaic/botanical vocabulary.

    # Words with unusual letter sequences that suggest Latin/Greek origin
    uncommon_bigrams = {'yx', 'xo', 'xf', 'ym', 'yp', 'vr', 'vl', 'wk',
                        'zl', 'zb', 'zm', 'bf', 'bv', 'pf', 'km', 'kn',
                        'gm', 'mf', 'mv', 'nm', 'wp', 'wn'}
    for i in range(len(word) - 1):
        if word[i:i+2] in uncommon_bigrams:
            score -= 2
            break

    # Penalize words ending in rare/technical patterns
    rare_endings = ('uous', 'uous', 'ial', 'ify', 'oid',
                    'ure', 'ous')
    # Actually let's be more targeted:
    # Words that are ROOT+ous where the root is obscure-sounding
    if word.endswith('ous') and len(word) >= 6:
        root_part = word[:-3]
        # If root part has unusual letters, it's probably obscure
        if any(c in root_part for c in 'xzqy') and len(root_part) <= 4:
            score -= 3

    return score


def merge_word_lists(existing, freq_words, sys_dict):
    """
    Build the expanded word list:
    1. Existing 10k words (with EXCLUDE_WORDS filtered out)
    2. Force-include words (guaranteed to be in the list)
    3. Frequency-ordered words validated against system dictionary
    4. Generated inflections of all words so far
    5. High-quality supplement from system dictionary (heavily filtered)
    6. Final inflection pass

    Force-include words go EARLY so they survive the 50k trim.
    """
    # --- Phase 1: Clean up existing 10k ---
    # Remove explicitly excluded words from the original 10k.
    # But preserve common short words that are in EXCLUDE_WORDS for subtitle
    # reasons but are legitimate keyboard words (am, oh, etc).
    # Only remove truly unwanted ones.
    HARD_EXCLUDE_FROM_CORE = {
        'wouldst', 'shouldst', 'couldst', 'dost', 'doth', 'hast', 'hath',
        'shalt', 'thou', 'thee', 'thy', 'thine', 'ye', 'forsooth', 'prithee',
        'perchance', 'methinks', 'betwixt', 'amongst', 'whilst',
        'streep', 'claude', 'whoo', 'dag', 'mala',
    }
    cleaned_existing = [w for w in existing if w not in HARD_EXCLUDE_FROM_CORE]
    removed = len(existing) - len(cleaned_existing)
    if removed:
        print(f"  Phase 1 - Cleaned {removed} bad words from original 10k")

    included = set(cleaned_existing)
    result = list(cleaned_existing)

    # --- Phase 2: Force-include words FIRST ---
    # These go right after the 10k core so they're guaranteed to survive trimming.
    force_added = 0
    for word in sorted(FORCE_INCLUDE):
        if word not in included and is_valid_word(word):
            result.append(word)
            included.add(word)
            force_added += 1
    print(f"  Phase 2 - Force-included: {force_added} words")

    # --- Phase 3: Frequency-ordered words validated by system dict ---
    freq_validated = []
    freq_rejected = 0

    for word, freq in freq_words:
        if word in included:
            continue
        if word in sys_dict:
            freq_validated.append((word, freq))
            included.add(word)
        else:
            freq_rejected += 1

    print(f"  Phase 3 - Frequency list: {len(freq_validated)} validated, "
          f"{freq_rejected} rejected (not in system dict)")
    result.extend([w for w, f in freq_validated])

    # --- Phase 4: Generated inflections ---
    # Use all words we have so far as bases for generating forms.
    # Pass the original 10k as high-priority bases so their inflections
    # get ranked higher (e.g., "running" from "run" > "spiritize" from "spirit").
    core_words = set(cleaned_existing)
    all_current = set(result)
    inflections = generate_inflections(all_current, sys_dict,
                                       high_priority_bases=core_words)

    inflection_added = 0
    for word, priority in inflections:
        if word not in included:
            result.append(word)
            included.add(word)
            inflection_added += 1

    print(f"  Phase 4 - Generated inflections (pass 1): {inflection_added} new words")

    # --- Phase 4b: Second inflection pass ---
    # Catch derivatives of derivatives (e.g., based on force-include words).
    # Only run if we haven't already overshot.
    if len(result) < TARGET_COUNT + 5000:
        all_current = set(result)
        inflections2 = generate_inflections(all_current, sys_dict,
                                            high_priority_bases=core_words)
        inflection_added_2 = 0
        for word, priority in inflections2:
            if word not in included:
                result.append(word)
                included.add(word)
                inflection_added_2 += 1
        if inflection_added_2:
            print(f"  Phase 4b - Generated inflections (pass 2): {inflection_added_2} new words")

    print(f"  After phases 2-4b: {len(result)} words")

    # --- Phase 5: Quality-scored supplement from system dictionary ---
    if len(result) < TARGET_COUNT:
        # Build a rank map: word -> position in our list.
        # Lower rank = more common (appeared earlier in frequency order).
        word_rank = {w: i for i, w in enumerate(result)}

        candidates = []
        for word in sys_dict:
            if word in included:
                continue
            if not is_valid_word(word):
                continue
            score = score_supplement_word(word, included, sys_dict,
                                          word_rank=word_rank)
            if score >= 6:  # Higher threshold — only genuinely useful words
                candidates.append((word, score))

        # Sort by score descending, then by word length (shorter = better),
        # then alphabetically for stability
        candidates.sort(key=lambda x: (-x[1], len(x[0]), x[0]))

        needed = TARGET_COUNT - len(result)
        supplement = candidates[:needed]
        if supplement:
            # Show score distribution
            scores = [s for _, s in supplement]
            print(f"  Phase 5 - System dict supplement: {len(supplement)} words "
                  f"(from {len(candidates)} candidates)")
            print(f"    Score range: {min(scores)} to {max(scores)}, "
                  f"median: {scores[len(scores)//2]}")

            # Show some samples at different score levels
            for s_word, s_score in supplement[:5]:
                print(f"    Top: {s_word} (score={s_score})")
            if len(supplement) > 10:
                mid = len(supplement) // 2
                for s_word, s_score in supplement[mid:mid+3]:
                    print(f"    Mid: {s_word} (score={s_score})")
            if len(supplement) > 5:
                for s_word, s_score in supplement[-3:]:
                    print(f"    Tail: {s_word} (score={s_score})")

            result.extend([w for w, s in supplement])
            included.update(w for w, s in supplement)

    # --- Phase 6: Final inflection pass on the full set ---
    # One more pass to catch inflections of supplement words
    if len(result) < TARGET_COUNT:
        all_current = set(result)
        inflections3 = generate_inflections(all_current, sys_dict,
                                            high_priority_bases=core_words)
        inflection_added_3 = 0
        for word, priority in inflections3:
            if word not in included and len(result) < TARGET_COUNT:
                result.append(word)
                included.add(word)
                inflection_added_3 += 1
        if inflection_added_3:
            print(f"  Phase 6 - Final inflection pass: {inflection_added_3} new words")

    # --- Smart trim to target ---
    # When trimming, preserve ALL force-include words and the original 10k.
    # Cut from the tail (least important words) first.
    if len(result) > TARGET_COUNT:
        # The force-include words are in the first ~10300 positions,
        # so a simple trim from the tail is safe.
        # But let's double-check by ensuring no FORCE_INCLUDE words are cut.
        force_set = FORCE_INCLUDE & included
        trimmed = result[:TARGET_COUNT]
        trimmed_set = set(trimmed)
        lost_force = force_set - trimmed_set
        if lost_force:
            # Some force-include words would be lost — inject them
            # by replacing the last N words in the trimmed list.
            lost_list = sorted(lost_force)
            print(f"  Rescuing {len(lost_list)} force-include words from trim")
            for i, word in enumerate(lost_list):
                trimmed[TARGET_COUNT - len(lost_list) + i] = word
        result = trimmed

    final = result[:TARGET_COUNT]
    return final


def quality_check(word_list):
    """Run quality checks on the final list."""
    print("\n=== QUALITY CHECK ===")

    word_set = set(word_list)

    # Check required words
    required = [
        'intuitively', 'definitively', 'comprehensively', 'simultaneously',
        'approximately', 'unfortunately', 'alternatively', 'enthusiastically',
        'immediately', 'particularly', 'significantly', 'independently',
        'automatically', 'traditionally', 'professionally', 'fundamentally',
        'extraordinarily', 'predominantly', 'consistently', 'continuously',
        'subsequently', 'substantially', 'overwhelmingly', 'retrospectively',
    ]
    missing = [w for w in required if w not in word_set]
    print(f"Required words: {len(required) - len(missing)}/{len(required)} present")
    if missing:
        print(f"  MISSING: {missing}")

    # Check common useful words
    common_check = [
        'the', 'is', 'are', 'was', 'were', 'have', 'has', 'had',
        'running', 'walking', 'talking', 'thinking', 'working',
        'beautiful', 'wonderful', 'important', 'different', 'possible',
        'because', 'between', 'through', 'however', 'although',
        'information', 'understanding', 'experience', 'development',
        'relationship', 'environment', 'organization', 'communication',
    ]
    common_missing = [w for w in common_check if w not in word_set]
    print(f"Common words: {len(common_check) - len(common_missing)}/{len(common_check)}")
    if common_missing:
        print(f"  Missing: {common_missing}")

    # Check adverb coverage
    adverb_check = [
        'quickly', 'slowly', 'carefully', 'easily', 'simply',
        'actually', 'basically', 'certainly', 'clearly', 'completely',
        'constantly', 'correctly', 'currently', 'deeply', 'directly',
        'entirely', 'especially', 'essentially', 'eventually', 'exactly',
        'extremely', 'finally', 'frequently', 'fully', 'generally',
        'gradually', 'greatly', 'happily', 'highly', 'hopefully',
        'incredibly', 'inevitably', 'initially', 'literally', 'mostly',
        'naturally', 'necessarily', 'normally', 'obviously', 'perfectly',
        'permanently', 'personally', 'potentially', 'previously', 'primarily',
        'probably', 'properly', 'rarely', 'recently', 'regularly',
        'relatively', 'repeatedly', 'seriously', 'significantly', 'slightly',
        'specifically', 'strongly', 'suddenly', 'supposedly', 'surely',
        'temporarily', 'typically', 'ultimately', 'unfortunately', 'usually',
    ]
    adverb_missing = [w for w in adverb_check if w not in word_set]
    print(f"Adverb check: {len(adverb_check) - len(adverb_missing)}/{len(adverb_check)}")
    if adverb_missing:
        print(f"  Missing: {adverb_missing}")

    # Check long-form adverbs (the main reason for this expansion)
    long_adverb_check = [
        'enthusiastically', 'comprehensively', 'simultaneously',
        'independently', 'approximately', 'alternatively',
        'internationally', 'environmentally', 'technologically',
        'psychologically', 'philosophically', 'mathematically',
        'scientifically', 'professionally', 'fundamentally',
        'extraordinarily', 'overwhelmingly', 'retrospectively',
        'systematically', 'hypothetically', 'theoretically',
        'unconditionally', 'unquestionably', 'coincidentally',
    ]
    long_missing = [w for w in long_adverb_check if w not in word_set]
    print(f"Long adverbs: {len(long_adverb_check) - len(long_missing)}/{len(long_adverb_check)}")
    if long_missing:
        print(f"  Missing: {long_missing}")

    # Duplicates
    if len(word_set) != len(word_list):
        dupes = len(word_list) - len(word_set)
        print(f"  WARNING: {dupes} duplicate words!")
    else:
        print(f"No duplicates")

    # Format check
    bad = [w for w in word_list if not re.match(r'^[a-z]+$', w)]
    if bad:
        print(f"  WARNING: {len(bad)} bad format: {bad[:10]}")
    else:
        print(f"All lowercase alpha")

    # Excluded word check — only flag truly bad ones that snuck past filtering.
    # Words in the original 10k (like "am", "oh") are intentionally kept since
    # they're legitimate keyboard words even if in EXCLUDE_WORDS for subtitle filtering.
    # Here we only check words AFTER the 10k boundary.
    leaked_after_10k = [w for w in word_list[10000:] if w in EXCLUDE_WORDS]
    if leaked_after_10k:
        print(f"  WARNING: {len(leaked_after_10k)} excluded words in expansion zone: {leaked_after_10k[:10]}")
    else:
        print(f"No excluded words in expansion zone")

    # Length distribution
    lengths = {}
    for w in word_list:
        bucket = len(w) if len(w) <= 18 else 19
        lengths[bucket] = lengths.get(bucket, 0) + 1
    print(f"\nLength distribution:")
    for k in sorted(lengths.keys()):
        label = f"{k}+" if k == 19 else f"{k}"
        bar = '#' * (lengths[k] // 200)
        print(f"  {label:>4s} chars: {lengths[k]:>5d} {bar}")

    # Samples from different regions
    print(f"\nSamples:")
    sample_positions = [0, 100, 500, 1000, 5000, 9999, 10000, 10050,
                        15000, 20000, 25000, 30000, 35000, 40000, 45000, 49999]
    for pos in sample_positions:
        if pos < len(word_list):
            print(f"  [{pos:>5d}]: {word_list[pos]}")

    # Tail quality check — show last 20 words
    print(f"\nLast 20 words (tail quality check):")
    for i, w in enumerate(word_list[-20:]):
        print(f"  [{len(word_list) - 20 + i}]: {w}")

    print(f"\nTotal: {len(word_list)} words")


def main():
    print("=== Expanding keyboard dictionary to 50k ===\n")

    # Load sources (read existing FIRST since we'll overwrite the same file)
    existing = load_existing_words()
    freq_words = download_frequency_list()
    sys_dict = load_system_dictionary()

    print()

    # Merge
    merged = merge_word_lists(existing, freq_words, sys_dict)

    # Remove duplicates while preserving order
    seen = set()
    deduped = []
    for w in merged:
        if w not in seen:
            deduped.append(w)
            seen.add(w)
    merged = deduped

    # Quality check
    quality_check(merged)

    # Write output
    with open(OUTPUT_FILE, 'w') as f:
        for word in merged:
            f.write(word + '\n')

    print(f"\nWritten {len(merged)} words to {OUTPUT_FILE}")


if __name__ == '__main__':
    main()
