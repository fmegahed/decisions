# Food recalls of Ohio firms

348 food recalls of firms in Ohio, with the class that the U.S. Food and
Drug Administration (FDA) gave to the recall. The class is an ordered
answer, from low to high risk. Use it to test a decision model on a
score question.

## Usage

``` r
ohio_recalls
```

## Format

A tibble with 348 rows and 8 columns:

- recall_number:

  Character. The recall number of the FDA.

- event_id:

  Character. The number of the recall event. One event can have more
  than one row, when its reasons or classes differ.

- recall_initiation_date:

  Date. The date on which the firm started the recall.

- city:

  Character. The city of the recalling firm.

- state:

  Character. The state of the recalling firm, always `"OH"`.

- product_description:

  Character. The description of the product, from the first product of
  the recall in the order of the API.

- reason_for_recall:

  Character. The reason for the recall, with the whitespace trimmed.

- classification:

  Ordered factor. The class of the FDA, from low to high risk:
  `Class III` \< `Class II` \< `Class I`. The data have 21 rows of Class
  III, 175 of Class II and 152 of Class I.

## Source

U.S. Food and Drug Administration. (n.d.). *Food recall enforcement
reports* \[Data set\]. openFDA. Retrieved October 23, 2026, from
<https://open.fda.gov/apis/food/enforcement/>

Filter: recalling firm in Ohio (`state:"OH"`), all years. The API gave
1,227 records on 2026-10-23.

## Details

openFDA data are in the public domain (CC0 1.0, see
<https://open.fda.gov/terms/>).

The classes come from 21 CFR 7.3(m):

- Class I: a reasonable probability that the use of, or exposure to, the
  product will cause serious adverse health consequences or death.

- Class II: the use of, or exposure to, the product may cause temporary
  or medically reversible adverse health consequences, or the
  probability of serious adverse health consequences is remote.

- Class III: the use of, or exposure to, the product is not likely to
  cause adverse health consequences.

One recall event often lists many products with the same reason. The
data keep one row for each unique event, trimmed reason and class (348
rows from 1,227 records), with the product of the first record in the
order of the API. The data keep no firm name, address or postal code.
Non-ASCII characters are changed to ASCII, for example an accented
letter to its plain letter.

## Examples

``` r
table(ohio_recalls$classification)
#> 
#> Class III  Class II   Class I 
#>        21       175       152 
ohio_recalls$reason_for_recall[1]
#> [1] "The firm stated that the product contains undeclared allergens."
```
