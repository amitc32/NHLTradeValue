# NHLTradeValue
An NHL trade evaluation algorithm made to test my coding ability for Ruby.

# Performance Model

Performance is built from several statistical components.

## Offensive Statistics

The offensive model considers:

- Points per 60
- Goals per 60
- Primary assists per 60
- Shots per 60

These statistics are converted into position-relative percentiles.

# Position-Specific Weighting

Different positions are evaluated differently.

## Defensemen

```text
Offense: 33.5%
Defense: 61.5%
TOI:      5.0%
```

Defense is deliberately weighted more heavily for defensemen.

This prevents elite offensive defensemen from receiving an artificially high Performance score solely because of their point production.

At the same time, the offensive component is still large enough for genuinely elite offensive defensemen to distinguish themselves.

---

## Centers

```text
Offense: 72.5%
Defense: 22.5%
TOI:      5.0%
```

Centers receive a strong offensive weighting while still receiving meaningful credit for defensive performance.

---

## Wingers

Both left and right wingers use:

```text
Offense: 74.5%
Defense: 20.5%
TOI:      5.0%
```

The model therefore places substantially more emphasis on offensive production for forwards.

---

# Defensive Model

Defense is divided into three major areas:

```text
Possession Defense      50%
Shutdown Defense        40%
Penalty Killing         10%
```

## Possession Defense

Possession defense uses:

| Metric | Weight |
|---|---:|
| xGF% | 45% |
| Fenwick% | 25% |
| Corsi% | 30% |

These statistics measure how effectively the player's team controls play while they are on the ice.

---

## Shutdown Defense

Shutdown defense considers:

| Metric | Weight |
|---|---:|
| 5v5 xGA/60 | 35% |
| Relative xGA/60 | 20% |
| Defensive-zone workload | 15% |
| Takeaways/60 | 10% |
| Blocked shots/60 | 10% |
| Defensive-zone giveaways/60 | 10% |

Metrics where lower values indicate better defensive performance are inverted before calculating their percentile.

---

## Penalty Killing

Penalty killing contributes 10% of the defensive score.

The model considers:

| Metric | Weight |
|---|---:|
| PK xGA/60 | 60% |
| PK GA/60 | 25% |
| PK workload | 15% |

This gives the model some ability to distinguish players who provide meaningful value while shorthanded.

---

# Percentile System

Most statistical measurements are converted to percentiles.

A player's percentile is based on their position and the current season.

For example:

```text
95th percentile
```

means the player performed better than approximately 95% of the relevant comparison population for that statistic.

Percentiles make different statistics easier to combine into a common 0–100 scoring system.

For defensive statistics where lower is better, the percentile is inverted.
