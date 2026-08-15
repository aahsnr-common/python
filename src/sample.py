"""
python file for practicing python
"""


def create_character(character_name, strength, intelligence, charisma):
    if not isinstance(character_name, str):
        return "The character name should be a string."
    if character_name == "":
        return "The character should have a name."
    if len(character_name) > 10:
        return "The character name is too long."
    if " " in character_name:
        return "The character name should not contain spaces."

    stats = [strength, intelligence, charisma]
    if any(type(stat) is not int for stat in stats):
        return "All stats should be integers."

    if any(stat < 1 for stat in stats):
        return "All stats should be no less than 1."

    if any(stat > 4 for stat in stats):
        return "All stats should be no more than 4."

    if sum(stats) != 7:
        return "The character should start with 7 points."
