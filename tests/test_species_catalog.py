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
