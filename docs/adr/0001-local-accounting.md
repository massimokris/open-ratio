# Preserve daily source totals and apply remembered categories

Store daily totals by stable activity source identity, with a separate remembered category map. Changing a category recalculates ratios, including history, without discarding measured time. Aggregate local data avoids retaining detailed browsing timelines; the trade-off is that historical ratios reflect current classification rather than the classification at capture time.

Persist local day identifiers as recorded instead of rebucketing history when the timezone changes. Ordinary measured intervals split at local midnight. Long gaps, sleep, session inactivity and clock discontinuities must not produce invented activity.
