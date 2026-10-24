# Severe injury reports from Ohio, 2025

Narratives of 464 severe work injuries in Ohio, with the injury type
that OSHA recorded. Use it to test a decision model on a text task with
five groups of different size.

## Usage

``` r
ohio_injuries
```

## Format

A tibble with 464 rows and 11 columns:

- id:

  Character. The report ID of OSHA.

- event_date:

  Date. The date of the event.

- city:

  Character. The city of the event.

- state:

  Character. The state, always `"OHIO"`.

- final_narrative:

  Character. The narrative that OSHA published, with the whitespace
  trimmed and each line break changed to a space.

- original_nature_title:

  Character. The nature of the injury, as OSHA titles it.

- collapsed_nature_title:

  Factor. The nature of the injury in five groups, in this order:
  `amputation` (187 rows), `fracture` (242), `crushing injury` (14),
  `thermal burn` (15) and `concussion` (6).

- original_event_title:

  Character. The event, as OSHA titles it.

- collapsed_event_title:

  Factor. The OIICS 2.01 division of the event, from the first digit of
  its code, in code order.

- original_source_title:

  Character. The source of the injury, as OSHA titles it.

- collapsed_source_title:

  Factor. The OIICS 2.01 division of the source, from the first digit of
  its code, in code order.

## Source

Occupational Safety and Health Administration. (n.d.). *Severe injury
reports* \[Data set\]. U.S. Department of Labor. Retrieved October 23,
2026, from <https://www.osha.gov/severe-injury-reports>

Filters: Year: 2025 and State: Ohio.

## Details

The data are a work of the U.S. government and are in the public domain.
The reports cover employers under federal OSHA jurisdiction. The OIICS
2.01 divisions come from the Occupational Injury and Illness
Classification System of the U.S. Bureau of Labor Statistics.

The five groups of `collapsed_nature_title` come from the titles of OSHA
like this:

- `amputation`: "Amputations, avulsions, enucleations unspecified" and
  "Amputations involving bone loss".

- `fracture`: "Fractures".

- `crushing injury`: "Nonfatal 'crushing' injuries".

- `thermal burn`: the three titles "Thermal burns" (degree unspecified,
  second degree, third degree or higher).

- `concussion`: "Concussions".

Three kinds of report are not in the data on purpose. The title
"Avulsions, enucleations without bone loss" is out, because OSHA does
not count an avulsion as an amputation. The combined titles "Fractures
and soft tissue injuries" and "Fractures and surface, flesh wounds" are
out, because they name more than one injury. The data keep no other
column of the download, for example the employer, the address and the
flag for an amputation.

## Examples

``` r
table(ohio_injuries$collapsed_nature_title)
#> 
#>      amputation        fracture crushing injury    thermal burn      concussion 
#>             187             242              14              15               6 
ohio_injuries$final_narrative[1]
#> [1] "An employee was removing a shaft from a dough machine for maintenance when their right little finger became caught and crushed in a pinch point. The employee sustained a partial amputation of the finger."
```
