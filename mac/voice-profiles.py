# Writes App/Previews/voices.json: each voice's gender, accent group and style, from what its source publishes.
# usage: python3 voice-profiles.py <phonon voices.jsonl> <kitten config.json>
#   Phonon: hf://gradium/phonon-voices voices.jsonl.  Kitten: hf://KittenML/kitten-tts-2-nano config.json.
import json, re, sys

phonon_jsonl, kitten_config = sys.argv[1:3]
groups = {"en-us": "American", "en-gb": "British", "characters": "Characters"}

# One or two words for each Phonon voice, taken from its description.
phonon_style = {
    "Zoey": "Playful", "Juniper": "Cheerful", "Everly": "Relaxed", "Harper": "Confident", "Hadley": "Kind",
    "Delia": "Low, grounded", "Easton": "Punchy", "Micah": "Energetic", "Trevor": "Upbeat", "Russell": "Motivating",
    "Preston": "Focused", "Miles": "Resonant", "Maeve": "Sparky", "Freya": "Bubbly", "Pippa": "Upbeat",
    "Elodie-Rose": "Enthusiastic", "Imogen": "Friendly", "Lottie": "Lively", "Alfie": "Punchy", "Hugh": "Soft",
    "Edwin": "Firm", "Spencer": "Patient", "Toby": "Sparky", "Teddy": "Quick", "Bryony": "Rich, relaxed",
    "Captain Silas Blackwater": "Gravelly pirate", "Morwenna of the Deep": "Husky, sultry",
    "Old Mortlake": "Raspy gravedigger", "Azgorath": "Deep demon", "Fennick the Young Elf": "Young elf",
    "The Thing Under the Stairs": "Growling monster", "Vyrmathrax the Ancient": "Deep dragon",
    "Grub the Ogre": "Gruff ogre", "Master Aldric": "Old wizard", "The Snow Queen": "Cold queen",
    "Sir Bramwell": "Pompous knight", "Fairy Godmother": "Warm grandmother",
}

phonon = {}
for line in open(phonon_jsonl):
    v = json.loads(line)
    if v["language"] != "en":
        continue
    phonon[v["name"]] = {"gender": v.get("gender"), "group": groups[v["locale"]], "style": phonon_style[v["name"]]}
phonon["default"] = {"gender": None, "group": None, "style": None}

# Kitten describes each voice as "Somber historian (female)". Its phonemes are American English.
kitten = {}
for v in json.load(open(kitten_config))["voices"]["en"]:
    style, gender = re.fullmatch(r"(.+) \((female|male)\)", v["description"]).groups()
    kitten[v["key"]] = {"gender": gender, "group": "American", "style": style}

# Pocket's voices come from recordings in kyutai/tts-voices. VCTK and EARS list their speakers' accents; the
# others give none. Kyutai named women's voices after women in Les Misérables and men's after men.
pocket = {
    "alba": {"gender": "female", "group": None, "style": "Casual"},     # alba-mackenna/casual
    "cosette": {"gender": "female", "group": None, "style": None},      # Expresso ex04
    "javert": {"gender": "male", "group": None, "style": None},         # a voice donation
    "marius": {"gender": "male", "group": None, "style": None},         # a voice donation
    "jean": {"gender": "male", "group": "American", "style": None},     # EARS p010, American English
    "fantine": {"gender": "female", "group": "British", "style": None},  # VCTK p244, English, Manchester
    "eponine": {"gender": "female", "group": "Scottish", "style": None},  # VCTK p262, Scottish, Edinburgh
    "azelma": {"gender": "female", "group": "Canadian", "style": None},   # VCTK p303, Canadian, Toronto
}

def clean(table):
    return {name: {k: v for k, v in p.items() if v is not None} for name, p in table.items()}

out = {"phonon": clean(phonon), "kitten": clean(kitten), "pocket": clean(pocket)}
with open("App/Previews/voices.json", "w") as f:
    json.dump(out, f, indent=1, ensure_ascii=False)
    f.write("\n")
