#####################################
# deaths ~ f(age; race; gender)
# model results, .R
# last edit: 2/8 (M.E)
#####################################

library(tidyverse)
library(lubridate)
library(rstanarm)
library(tidybayes)
library(RColorBrewer)
library(modelr)

setwd("~/Projects/pnas")
theme_set(theme_tidybayes())
options(mc.cores = parallel::detectCores())

cols = c(
	brewer.pal(8, 'Set2'), 
	brewer.pal(8, 'Set3'), 
	brewer.pal(8, 'Set1')
)

# ... attach imputed data 
# ... update with fe_pop_imputed_00_18.csv on OSF
dat = read_csv('./data/fe_pop_imputed.csv') 

# .... let's just go for first imputation for now (will stack)
df2 = dat %>%
	filter(.imp == 1) %>%
	mutate(
		age_group = fct_relevel(age, "5-9", after = 2),
		age_c = as.numeric(age_group)
	) 
# ... models
# ... baseline: simple, independent intercept shifts
m0 =  stan_glmer(
		deaths ~ race + sex + (1 | age_group) + (1 | year),
		offset = log(pop),
		data = df2, 
		family = 'neg_binomial_2'
	)

# ... m_1: race x gender interaction 
# ... m_2: race x gender effects depends on age group
# ... m_3: race x gender effects depends on year
m1 = update(m0, formula = deaths ~ race*sex + (1 | age_group) + (1 | year))
m2 = update(m0, formula = deaths ~ race*sex + (race + sex + race*sex | age_group) + (1 | year), adapt_delta = .9999)
m3 = update(m0, formula = deaths ~ race*sex + (1 | age_group) + (race + sex + race*sex | year))

# saveRDS(m0, 'm0.rds')
# saveRDS(m1, 'm1.rds')
# saveRDS(m2, 'm2.rds')
# saveRDS(m3, 'm3.rds')

m0 = read_rds('m0.rds')
m1 = read_rds('m1.rds')
m2 = read_rds('m2.rds')
m3 = read_rds('m3.rds')

# ... what do year effects look like?
m2 %>% 
	spread_draws(b[, group]) %>% 
	median_qi(.width = c(.5, .9)) %>% 
	separate(group, c("group", "value"), ":") %>%
	filter(group == 'year') %>%
	ggplot(., aes(x = value, y = b, ymin = .lower, ymax = .upper)) + 
	geom_hline(yintercept = 0, size = 1.5, alpha = .25, color = cols[8]) + 
	geom_errorbar(aes(group = .width, size = .width), width = 0, color = cols[13]) +
	geom_point(fill = cols[9], pch = 21, size = 3.5)  +
	scale_size(range = c(1.5, .5), breaks = c(.5, .90)) +
    ylab(expression(beta)) +
    theme_minimal() +
    theme(legend.position = 'bottom')

# ... and predicted age x sex x race risks across the models
scens = df2 %>%
    data_grid(
        age_group,
        sex,
        race,
        pop = 100000000,
        year = 0
    ) 

pR = function(.sims, .mod){
	.sims %>% 
		add_predicted_draws(.mod) %>%
		median_qi(.width = .5) %>%
		ggplot(., 
           aes(x = age_group, 
               y = .prediction/1000,
               ymin = .lower/1000, ymax = .upper/1000,
               group = race, color = race, fill = race
           )
    ) + 
    geom_ribbon(color = 'grey100', alpha = .25) +
    geom_line(size = 1.45) +
    facet_wrap(~sex, scale = 'free_y') +
    scale_color_manual(values = cols[c(9, 12, 3, 8, 16)]) + 
    scale_fill_manual(values  = cols[c(9, 12, 3, 8, 16)]) +
    theme_tidybayes() +
    theme(
    	axis.text.x = element_text(angle = 90, vjust = 0.5),
    	legend.title = element_blank()
    )
}

# ... plot it out
pR(scens, m0)
pR(scens, m1)
pR(scens, m2)

df2 %>%
    data_grid(
        age_group,
        sex,
        race,
        pop = 100000000,
        year
    ) %>% 
    add_predicted_draws(m4) %>%
    filter(sex == 'Male') %>%
    median_qi(.width = .5) %>%
    ggplot(., aes(x = age_group, 
               y = .prediction/1000,
               ymin = .lower/1000, ymax = .upper/1000,
               group = year, color = factor(year), fill = year
           )
    ) +
    geom_line() +
    facet_wrap(~race, scale = 'free_y') +
    theme_tidybayes() +
    theme(
    	axis.text.x = element_text(angle = 90, vjust = 0.5),
    	legend.title = element_blank()
    ) +
    scale_color_brewer(palette = 'Dark2')

# ... are any of these strongly preferred? 
# ... CV evdence 
loo0 = loo(m0)
loo1 = loo(m1)
loo2 = loo(m2)
loo3 = loo(m3)

compare_models(loo0, loo1) # ... race x gender interaction is informative
compare_models(loo1, loo2) # ... race x gender x age is informative over just r x g
compare_models(loo1, loo3) # ... year interaction doesn't do much over r x g only model

# ... and, stacking weight evidence
loo_model_weights(list(loo0, loo1, loo2, loo3, loo4))

# ... expected values too
scens %>%
    add_fitted_draws(m2) %>%
    mutate(.value = .value/1000) %>%
    median_qi(.width = .5) %>%
    ggplot(., 
           aes(x = age_group, 
               y = .value,
               ymin = .lower, ymax = .upper,
               group = race, color = race, fill = race
           )
    ) + 
    geom_ribbon(color = 'grey100', alpha = .5) +
    geom_line(size = 1.45) +
    facet_wrap(~sex, scale = 'free_y') +
    scale_color_manual(values = cols[c(9, 12, 3, 8, 16)]) + 
    scale_fill_manual(values  = cols[c(9, 12, 3, 8, 16)]) 

### IN PROGRESS
# ... what do time trends look like?
df2 %>% 
    ggplot(., aes(x = year, y = deaths, group = race, color = race, fill = race)) +
    geom_smooth(method = 'loess', span = 2, se = FALSE, alpha = .15) + 
    facet_wrap(~sex, scale = 'free_y')

# ... looks like increase across time is mostly among whites, particularly men
df2 %>% 
    ggplot(., aes(x = year, y = deaths, group = race, color = race, fill = race)) +
    geom_smooth(method = 'lm', span = 1, se = TRUE, alpha = .15) + 
    facet_wrap(~sex, scale = 'free_y')

# ... age patterns seem consistent across years, outside of small groups
df2 %>% 
    filter(sex == 'Male') %>%
    ggplot(., aes(x = age_c, y = deaths, group = year, color = year)) +
    geom_smooth(se = FALSE) +
    facet_wrap(~race)

# ... female pop much more noisey (makes sense; much smaller counts)
df2 %>% 
    filter(sex == 'Female') %>%
    ggplot(., aes(x = age_c, y = deaths, group = year, color = year)) +
    geom_smooth(se = FALSE) +
    facet_wrap(~race)

# ... looks like stratifying is the way to go
stratR = function(.sim_data){

    # ... fit indpedent model
    m0 = .sim_data %>%
        stan_glmer(
            deaths ~ 1 + (1 | year) + (1 | age_group),
            offset = log(pop),
            data = .,
            family = 'neg_binomial_2',
            adapt_delta = .99#,
            #iter = 500
        )

    # ... fit conditional model
    m1 = .sim_data %>%
        stan_glmer(
            deaths ~ 1 + (1 | year) + (1 | age_group) + (1 | year:age_group),
            offset = log(pop),
            data = .,
            family = 'neg_binomial_2',
            adapt_delta = .99#,
            #iter = 500
        )

    # ... get fit measures
    loo_m0 = loo(m0, k_threshold = 0.7)
    loo_m1 = loo(m1, k_threshold = 0.7)
    loo_comp = compare_models(loo_m0, loo_m1)
    m_weights = loo_model_weights(list(loo_m0, loo_m1))

    # ... and fitted + predicted values
    scen = .sim_data %>%
        data_grid(
            age_group,
            pop = 100000000,
            year
        ) 

    fit_m0 = scen %>% add_fitted_draws(m0)
    fit_m1 = scen %>% add_fitted_draws(m1)

    pred_m0 = scen %>% add_predicted_draws(m0)
    pred_m1 = scen %>% add_predicted_draws(m1)

    # ... plot of estimated values across years
    fit_plot = bind_rows(
        fit_m0 %>% median_qi(.width = .90) %>% mutate(model = 'm0'),
        fit_m1 %>% median_qi(.width = .90) %>% mutate(model = 'm1')
    ) %>%
    ggplot(.,
        aes(x = age_group,
            y = .value/1000, 
            group = model, 
            color = model)
    ) + 
    geom_line() +
    facet_wrap(~year) +
    theme(axis.text.x = element_text(angle = 90, vjust = 0.5)) 


    # ... plot draws from predictive draws
    pred_plot = pred_m0 %>%
            filter(year %in% c(2010, 2013, 2016)) %>%
            ggplot(., 
                aes(x = age_group, y = .prediction/1000, group = year)
            ) +
            geom_count(alpha = .25, color = cols[8]) +
            geom_boxplot(aes(group = age_group), outlier.shape = NA, fill = cols[9]) +
            facet_wrap(~year) +
            theme(
                axis.text.x = element_text(angle = 90, vjust = 0.5),
                legend.position = 'bottom'
            ) 

    # ... just return everything
    return(
        list(
            m0 = m0,
            m1 = m1, 
            loo_0 = loo_m0, 
            loo_1 = loo_m1,
            loo_comp = loo_comp,
            m_weights = m_weights,
            fit_m0 = fit_m0,
            fit_m1 = fit_m1,
            pred_m0 = pred_m0,
            pred_m1 = pred_m1, 
            fit_plot = fit_plot,
            pred_pot = pred_plot
        )
    )
}

# sim_df = tibble(
#             group_id = c('bm', 'wm', 'lm', 'am', 'nm', 'bf', 'wf', 'lf', 'af', 'nf'),
#             group_data = list(
#                  df2 %>% filter(race == 'black',  sex == 'Male'), 
#                  df2 %>% filter(race == 'white',  sex == 'Male'),
#                  df2 %>% filter(race == 'latino', sex == 'Male'),
#                  df2 %>% filter(race == 'asian',  sex == 'Male'),
#                  df2 %>% filter(race == 'amind',  sex == 'Male'),
#                  df2 %>% filter(race == 'black',  sex == 'Female'),
#                  df2 %>% filter(race == 'white',  sex == 'Female'),
#                  df2 %>% filter(race == 'latino', sex == 'Female'),
#                  df2 %>% filter(race == 'asian',  sex == 'Female'),
#                  df2 %>% filter(race == 'amind',  sex == 'Female')
#             )
#         ) %>%
#         mutate(group_res = map(group_data, ~stratR(.x)))
# save_rds(sim_df, 'sims.rds')       

# ... if just want to re-run individually 
bm = df2 %>% filter(race == 'black',  sex == 'Male') %>% stratR(.)
wm = df2 %>% filter(race == 'white',  sex == 'Male') %>% stratR(.)
lm = df2 %>% filter(race == 'latino', sex == 'Male') %>% stratR(.)
am = df2 %>% filter(race == 'asian',  sex == 'Male') %>% stratR(.)
nm = df2 %>% filter(race == 'amind',  sex == 'Male') %>% stratR(.)

bf = df2 %>% filter(race == 'black',  sex == 'Female') %>% stratR(.)
wf = df2 %>% filter(race == 'white',  sex == 'Female') %>% stratR(.)
lf = df2 %>% filter(race == 'latino', sex == 'Female') %>% stratR(.)
af = df2 %>% filter(race == 'asian',  sex == 'Female') %>% stratR(.)
nf = df2 %>% filter(race == 'amind',  sex == 'Female') %>% stratR(.)


coef(bm$m0)
coef(bm$m1)

# ... does a spline work
# ... offset argument failing in rstanarm? 
m_gam = stan_gamm4(
    deaths ~ s(age_c) + race + sex,
    data = df2,
    random = ~ (1 | year),
    offset = log(pop),
    family = 'neg_binomial_2'
)

# ... move over to brms for now
library(brms)
df3 = df2 %>% 
    mutate(year_f = factor(year)) %>% 
    filter(race == 'black',  sex == 'Female')

m_test0 = brm(
    deaths ~ s(age_c) + year_f + offset(I(log(pop))),
    data = df3,
    family = "negbinomial",
    control = list(adapt_delta = 0.99, max_treedepth = 15)
)

m_test1 = brm(
    deaths ~ s(age_c, by = year_f) + offset(I(log(pop))),
    data = df3,
    family = "negbinomial",
    control = list(adapt_delta = 0.99, max_treedepth = 15)
)

# ... a handful of problematic points from second model; don't compare
l_test0 = loo(m_test0)
l_test1 = loo(m_test1, reloo = TRUE)

# ... so, weak evidence favoring m0
compare_ic(l_test0, l_test1)

# ... prefers model 1 but some weight on model 2
ws = loo_model_weights(list(l_test0, l_test1))

# ... let's take a look at what predictions look like
test = df3 %>% data_grid(age_c, year_f, pop = 100000000)

# ... loooooks finnnnnne
pp_average(
    m_test0, m_test1, 
    weights = ws, method = 'fitted',
    newdata = test
) %>% 
    tbl_df() %>%
    bind_cols(test) %>%
    ggplot(., aes(y  = Estimate/10000, x = age_c, group = year_f, color = year_f)) +
    geom_line() 


df3 %>%
    data_grid(age_c, year_f, pop = 100000000) %>%
    add_fitted_draws(m_test1) %>%
    median_qi(.width = .9) %>%
    ggplot(.,
           aes(
            x = age_c, 
            y = .value/1000,
            group = year_f, 
            color = year_f,
            fill = year_f
        )
    ) +
    geom_line() +
    scale_color_manual(values = cols[c(9, 11, 12, 13, 14, 15, 16)]) 


df3 %>%
    data_grid(age_c, year_f, pop = 100000000) %>%
    add_fitted_draws(m_test1) %>%
    median_qi(.width = .9) %>%
    ggplot(.,
           aes(
            x = age_c, 
            y = .value/1000, ymin = .lower/1000, ymax = .upper/1000,
            group = year_f, 
            color = year_f,
            fill = year_f
        )
    ) + 
    geom_ribbon(color = 'grey100') + 
    geom_line(color = 'grey1') + 
    facet_wrap(~year_f) +
    scale_color_manual(values = cols[c(9, 11, 12, 13, 14, 15, 16)]) +
    scale_fill_manual(values = cols[c(9, 11, 12, 13, 14, 15, 16)]) 


# ... again, for big groups, patterns the same

# ... do bigger shifts appear in random effects model
# ... random effect deviation slightly more conservative
df2 %>%
    data_grid(age_group, year, pop = 100000000) %>%
    add_fitted_draws(wm$m0) %>%
    median_qi(.width = .5)  %>%
    ggplot(.,
           aes(x = age_group, y = .value/1000, group = year, color = year)
    ) + 
    geom_line() 


# plot draws version
df3 %>%
    data_grid(age_c, year_f, pop = 100000000) %>%
    add_predicted_draws(m_test0, n = 500) %>%
    ggplot(., aes(
        x = age_c, y = .prediction/1000, 
        group = .draw,
        color = year_f)
    ) +
    geom_line(alpha = .1, size = .5) +
    facet_wrap(~year_f) +
    scale_color_brewer(palette = 'Set3') +
    theme(legend.position = 'none')

cols[9, 11, 12, 13, 8, 14]


