import json

from app.config import ROOT
from app.species_catalog import birdnet_label_map, load_hangzhou_birdnet_catalog


def test_shared_hangzhou_catalog_contains_200_unique_species():
    species = load_hangzhou_birdnet_catalog()
    assert len(species) == 200
    assert len({item.output_index for item in species}) == 200
    assert len(birdnet_label_map()) == 200


def test_shared_hangzhou_catalog_keeps_verified_species():
    names = {item.scientific_name for item in load_hangzhou_birdnet_catalog()}
    assert {
        "Copsychus saularis",
        "Pycnonotus sinensis",
        "Turdus mandarinus",
        "Streptopelia chinensis",
        "Urocissa erythroryncha",
        "Gallinula chloropus",
    } <= names


def test_shared_catalog_uses_complete_simplified_chinese_name_map():
    mapping = json.loads(
        (ROOT / "ml" / "configs" / "bird_species_zh_cn.json").read_text(
            encoding="utf-8"
        )
    )
    preferred = mapping["names"]
    species = load_hangzhou_birdnet_catalog()

    assert mapping["species_count"] == 200
    assert {item.scientific_name for item in species} == set(preferred)
    assert all(
        item.name_zh == preferred[item.scientific_name]["name_zh_cn"]
        for item in species
    )
    assert all(item.source_name_zh for item in species)

    known_conversions = {
        "Egretta garzetta": ("小白鹭", "小白鷺"),
        "Motacilla alba": ("白鹡鸰", "白鶺鴒"),
        "Sinosuthora webbiana": ("粉红鹦嘴", "粉紅鸚嘴"),
        "Spodiopsar sericeus": ("丝光椋鸟", "絲光椋鳥"),
    }
    by_scientific_name = {item.scientific_name: item for item in species}
    for scientific_name, (simplified, source) in known_conversions.items():
        assert by_scientific_name[scientific_name].name_zh == simplified
        assert by_scientific_name[scientific_name].source_name_zh == source
