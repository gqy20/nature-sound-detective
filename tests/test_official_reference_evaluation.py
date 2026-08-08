import numpy as np
import pytest

from scripts.evaluate_challenge_nonbird_official import repeat_consistency


def test_repeat_consistency_reports_probability_and_decision_drift():
    baseline = np.asarray([[0.9, 0.1], [0.2, 0.8]], dtype=np.float32)
    changed = baseline.copy()
    changed[1, 0] += 0.01
    accepted = baseline >= 0.5
    changed_accepted = accepted.copy()
    changed_accepted[1, 0] = True

    report = repeat_consistency(
        [baseline, changed], [accepted, changed_accepted]
    )

    assert report["repeats"] == 2
    assert report["max_probability_delta"] == pytest.approx(0.01, abs=1e-6)
    assert report["inconsistent_windows"] == 1
    assert report["consistent_window_rate"] == 0.5
