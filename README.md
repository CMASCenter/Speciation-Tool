## Welcome to Speciation Tool GitHub Repository

Chemical Transport Models (CTMs) account for chemistry occurring in the atmosphere by using a chemical mechanism with multiple chemical reactions and species.  Gas-phase chemical mechanisms that are widely used in CTMs include the Carbon Bond mechanisms (CB05, CB6) and Statewide Air Pollution Research Center mechanisms (SAPRC07, SAPRC11). Aerosol- phase chemistry schemes tend to be specific to individual CTMs. The Community Multiscale Air Quality Model (CMAQ) has aerosol schemes named AE6 and AE7 whereas the Comprehensive Air quality Model with extensions (CAMx) has aerosol schemes named CF2 and CMU.

Emission rates are an essential CTM input, and chemical species provided in the inputs must exactly match the model species of the CTM, although some CTMs like CMAQ allow for chemical mapping online. Emission input files are generated from data provided by emission inventories. However, emission inventories are prepared in terms of regulated pollutants such as carbon monoxide (CO), nitrogen oxides (NOx), volatile organic compounds (VOC), and particulate matter (PM). Some inventory pollutants exactly correspond to a single model species (e.g., CO) but most inventory pollutants correspond to several model species, e.g., inventory pollutant NOx corresponds to model species NO and NO2. Another potential complication is that chemical mechanisms tend to have different model species, especially for VOC, and so a CTM requires emission inputs with different model species for a simulation using the CB6 vs. SAPRC07 chemical mechanism.

The purpose of the Speciation Tool is to translate from emission inventory pollutants to CTM emission input species by:
- Creating “split factors” that allocate inventory pollutants (e.g., VOC, PM2.5) to model species (e.g., formaldehyde as part of VOC, elemental carbon as part of PM2.5)
- Naming model species correctly (e.g., formaldehyde as HCHO or FORM) to be recognized by the CTM

The split factors output by the Speciation Tool are input data needed by emission processing software such as the Sparse-Matrix Operating Kernel for Emissions (SMOKE).

Generally, CTM emission inputs are created from emission inventories of criteria air pollutant (CAPS) such as the EPA’s National Emissions Inventory (NEI). However, the NEI also contains toxic air pollutants, also known as hazardous air pollutants (HAPS). It can be advantageous to combine information from CAPS and HAPS into a unified modeling emission inventory of toxic and other species. Taking formaldehyde as an example, processing the NEI VOC emission estimates for modelling will produce formaldehyde emissions estimates that could then be replaced by explicit estimates of formaldehyde emissions from the NEI. Implementing this strategy, named integration, requires coordinating the generation of split factors (by the Speciation Tool) with the emission processing (by SMOKE). The Speciation Tool supports the integration CAPS and HAPS emission estimates as an option.



You can use the [editor on GitHub](https://github.com/CMASCenter/Speciation-Tool/edit/master/README.md) to maintain and preview the content for your website in Markdown files.

Whenever you commit to this repository, GitHub Pages will run [Jekyll](https://jekyllrb.com/) to rebuild the pages in your site, from the content in your Markdown files.

### Markdown

Markdown is a lightweight and easy-to-use syntax for styling your writing. It includes conventions for

```markdown
Syntax highlighted code block

# Header 1
## Header 2
### Header 3

- Bulleted
- List

1. Numbered
2. List

**Bold** and _Italic_ and `Code` text

[Link](url) and ![Image](src)
```

For more details see [GitHub Flavored Markdown](https://guides.github.com/features/mastering-markdown/).

### Jekyll Themes

Your Pages site will use the layout and styles from the Jekyll theme you have selected in your [repository settings](https://github.com/CMASCenter/Speciation-Tool/settings). The name of this theme is saved in the Jekyll `_config.yml` configuration file.

### Support or Contact

Having trouble with Pages? Check out our [documentation](https://help.github.com/categories/github-pages-basics/) or [contact support](https://github.com/contact) and we’ll help you sort it out.
