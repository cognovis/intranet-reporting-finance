# /packages/intranet-reporting-finance/www/finance-expense-bundles.tcl
#
# Copyright (C) 2003-2006 ]project-open[
#
# All rights reserved. Please check
# http://www.project-open.com/ for licensing details.

ad_page_contract {
	testing reports	
    @param start_year Year to start the report
    @param start_unit Month or week to start within the start_year
} {
    { start_date "2010-01-01" }
    { end_date "2012-01-01" }
    { output_format "html" }
    { cost_status_id "3802" }
    { employee_id "" }
}

# ------------------------------------------------------------
# Security

# Label: Provides the security context for this report
# because it identifies unquely the report's Menu and
# its permissions.
set menu_label "reporting-finance-expenses"
set current_user_id [ad_maybe_redirect_for_registration]
set read_p [db_string report_perms "
	select	im_object_permission_p(m.menu_id, :current_user_id, 'read')
	from	im_menus m
	where	m.label = :menu_label
" -default 'f']

if {![string equal "t" $read_p]} {
    set msg [lang::message::lookup "" intranet-reporting.You_dont_have_permissions "You don't have the necessary permissions to view this page"]
    ad_return_complaint 1 "<li>$msg"
    return
}

# Check if the intranet-expenses module is installed
if {[catch {
    set package_id [im_package_expenses_id]
} err_msg]} {
    set msg [lang::message::lookup "" intranet-reporting.Expense_module_not_installed "The Expense module 'intranet-expenses' is not installed in your system, so this report wouldn't work."]
    ad_return_complaint 1 "<li>$msg"
    return
}

# Check that Start & End-Date have correct format
if {"" != $start_date && ![regexp {^[0-9][0-9][0-9][0-9]\-[0-9][0-9]\-[0-9][0-9]$} $start_date]} {
    ad_return_complaint 1 "Start Date doesn't have the right format.<br>
    Current value: '$start_date'<br>
    Expected format: 'YYYY-MM-DD'"
}

if {"" != $end_date && ![regexp {^[0-9][0-9][0-9][0-9]\-[0-9][0-9]\-[0-9][0-9]$} $end_date]} {
    ad_return_complaint 1 "End Date doesn't have the right format.<br>
    Current value: '$end_date'<br>
    Expected format: 'YYYY-MM-DD'"
}

# ------------------------------------------------------------
# Page Settings

set page_title "Expense Bundles"
set context_bar [im_context_bar $page_title]
set context ""

set help_text "
"

# ------------------------------------------------------------
# Defaults

set level_of_detail 2

set rowclass(0) "roweven"
set rowclass(1) "rowodd"

set days_in_past 7

set default_currency [ad_parameter -package_id [im_package_cost_id] "DefaultCurrency" "" "EUR"]
set cur_format [im_l10n_sql_currency_format]
set date_format [im_l10n_sql_date_format]

db_1row todays_date "
select
	to_char(sysdate::date - :days_in_past::integer, 'YYYY') as todays_year,
	to_char(sysdate::date - :days_in_past::integer, 'MM') as todays_month,
	to_char(sysdate::date - :days_in_past::integer, 'DD') as todays_day
from dual
"

if {"" == $start_date} {
    set start_date "$todays_year-$todays_month-01"
}


db_1row end_date "
select
	to_char(to_date(:start_date, 'YYYY-MM-DD') + 31::integer, 'YYYY') as end_year,
	to_char(to_date(:start_date, 'YYYY-MM-DD') + 31::integer, 'MM') as end_month,
	to_char(to_date(:start_date, 'YYYY-MM-DD') + 31::integer, 'DD') as end_day
from dual
"

if {"" == $end_date} {
    set end_date "$end_year-$end_month-01"
}

set expense_url "/intranet-expenses/new?form_mode=display&expense_id="
set user_url "/intranet/users/view?user_id="

set this_url [export_vars -base "/intranet-reporting-finance/finance-expense-bundles" {start_date end_date project_id} ]


# ------------------------------------------------------------
# Conditional SQL Where-Clause
#

set currency_select [list] 
set currency_columns "" 
set currency_var_columns "" 

foreach currency [im_supported_currencies] {
    lappend currency_select "
	(select 
	 round(sum(coalesce(co.amount * (1 + co.vat / 100),0)) :: numeric, 2) 
	 from 
		 im_costs co 
		 LEFT OUTER JOIN 
		 (select * from im_expenses) exp on (co.cost_id = exp.expense_id) where co.currency = '$currency' and exp.bundle_id = c.cost_id
	 ) as $currency
    "
    append currency_columns "\"$currency\"\n"
    append currency_var_columns "\"$[string tolower $currency]\" "
	
}

set currency_clause [join $currency_select ",\n"]

set criteria [list]

if { ![empty_string_p $employee_id] } {
    lappend criteria "c.provider_id = $employee_id"
}

if { ![empty_string_p $cost_status_id] } {
    lappend criteria "c.cost_status_id = $cost_status_id"
}

if {"" != $start_date} {
    lappend criteria "c.effective_date >= :start_date::timestamptz"
}

if {"" != $end_date} {
    lappend criteria "c.effective_date < :end_date::timestamptz"
}

set where_clause [join $criteria " and\n            "]
if { ![empty_string_p $where_clause] } {
    set where_clause " and $where_clause"
}


# ------------------------------------------------------------
# Define the report - SQL, counters, headers and footers
#


set def_curr [parameter::get -package_id [apm_package_id_from_key intranet-cost] -parameter "DefaultCurrency" -default 'EUR']

set sql "
select 
	c.cost_id,
	c.cost_name, 
	c.provider_id as employee_id,
	(select im_name_from_user_id(c.provider_id)) as employee_name,
	(select round((c.amount * (1 + c.vat / 100)):: numeric,2)) as amount_incl_vat,
	(select 
		sum(coalesce(t.amount_reimbursable,0)) 
	from (
		select 
			e.expense_id, 
			e.reimbursable,
			(select 
				round((
					select round(
						(co.amount * (1 + co.vat / 100)) * im_exchange_rate(co.effective_date::date, co.currency, '$def_curr') 
					:: numeric, 2)
					from im_costs co
					where co.cost_id = e.expense_id
					) * (e.reimbursable/100) :: numeric, 2
				)
			) as amount_reimbursable 
		from 
			im_expenses e
		where 
			e.bundle_id = c.cost_id
		) t
	) as sum_amount_reimbursable,
	$currency_clause	
from 
        im_costs c
where
	c.cost_type_id = 3722
	$where_clause 
"

set total 0
set employee_subtotal 0
set employee_subtotal_vat_reimburse 0

# -------------------------------------------------------------------------------------------------
	
# Global header/footer
set header0 {"Employee" "Bundle" "Owed to employee" "Total" "AUD" "CAD" "CHF" "EUR" "GBP" "JPY" "USD"}

set header0_string "\"Employee\" \"Bundle\" \"Owed to employee\" \"Total\" "
append header0_string $currency_columns 
set header0 $header0_string

set footer0 { }

set total_amount_reimbursable_counter [list \
        pretty_name "Total Amount Reimbursable" \
        var total_amount_reimbursable \
        reset 0 \
        expr "\$sum_amount_reimbursable+0" \
]

set counters [list \
	$total_amount_reimbursable_counter \
]

set report_def_string ""
append report_def_string "group_by employee_id \ "
append report_def_string "header {\"\\#colspan=11 \$employee_name\" } \ "
append report_def_string "content \ "
append report_def_string "{header {"
append report_def_string "\"\" "
append report_def_string "                                    \"\$cost_name\""
append report_def_string "                                     \"\$sum_amount_reimbursable\""
append report_def_string "                                     \"\$amount_incl_vat\" "
append report_def_string $currency_var_columns
append report_def_string "                                 } \ "
append report_def_string "                                content {} \ "
append report_def_string "                                 footer {} \ "
append report_def_string "                  } footer {} \ "

set report_def $report_def_string

# ------------------------------------------------------------
# Constants
#

set start_years {2004 2004 2005 2005 2006 2007 2008 2009 2010 2011 2012 2013 2014 2015 2016 2017 2018 2019 2020 }
set start_months {01 Jan 02 Feb 03 Mar 04 Apr 05 May 06 Jun 07 Jul 08 Aug 09 Sep 10 Oct 11 Nov 12 Dec}
set start_weeks {01 1 02 2 03 3 04 4 05 5 06 6 07 7 08 8 09 9 10 10 11 11 12 12 13 13 14 14 15 15 16 16 17 17 18 18 19 19 20 20 21 21 22 22 23 23 24 24 25 25 26 26 27 27 28 28 29 29 30 30 31 31 32 32 33 33 34 34 35 35 36 36 37 37 38 38 39 39 40 40 41 41 42 42 43 43 44 44 45 45 46 46 47 47 48 48 49 49 50 50 51 51 52 52}
set start_days {01 1 02 2 03 3 04 4 05 5 06 6 07 7 08 8 09 9 10 10 11 11 12 12 13 13 14 14 15 15 16 16 17 17 18 18 19 19 20 20 21 21 22 22 23 23 24 24 25 25 26 26 27 27 28 28 29 29 30 30 31 31}

# ------------------------------------------------------------
# Start formatting the page
#

# Write out HTTP header, considering CSV/MS-Excel formatting
im_report_write_http_headers -output_format $output_format

# Add the HTML select box to the head of the page
switch $output_format {
    html {
        ns_write "
	[im_header]
	[im_navbar]
	
	<table cellspacing=0 cellpadding=0 border=0>
	<tr valign=top>
	<td>
	<form>
                <!--[export_form_vars employee_id]-->
		<table border=0 cellspacing=1 cellpadding=1>
		<tr>
		  <td class=form-label>Start Date</td>
		  <td class=form-widget>
		    <input type=textfield name=start_date value=$start_date>
		  </td>
		</tr>
		<tr>
		  <td class=form-label>End Date</td>
		  <td class=form-widget>
		    <input type=textfield name=end_date value=$end_date>
		  </td>
		</tr>
                <tr>
                  <td class=form-label>User</td>
                  <td class=form-widget>
                    [im_user_select -include_empty_p 1 -group_id [list [im_employee_group_id] [im_freelance_group_id]] -include_empty_name [lang::message::lookup "" intranet-core.All "All"] employee_id $employee_id]
                </td>
                </tr>
                <tr>
                  <td class=form-label>Bundle Status</td>
                  <td class=form-widget>
                        [im_category_select -include_empty_p 1 "Intranet Cost Status" cost_status_id $cost_status_id]
                  </td>
                </tr>
		<tr>
		  <td class=form-label></td>
		  <td class=form-widget><input type=submit value=Submit></td>
		</tr>
		</table>
	</form>
	</td>
	<td align=center>
		<table cellspacing=2 width=90%>
		<tr><td>$help_text</td></tr>
		</table>
	</td>
	</tr>
	</table>
	
	<table border=0 cellspacing=1 cellpadding=1>\n"
    }
}
	
im_report_render_row \
    -output_format $output_format \
    -row $header0 \
    -row_class "rowtitle" \
    -cell_class "rowtitle"


set footer_array_list [list]
set last_value_list [list]
set class "rowodd"
set expense_payment_type_length 13
set note_length 20

ns_log Notice "intranet-reporting-finance/finance-expenses-bundles.tcl: sql=\n$sql"

set first_loop_p 1
set currency list
array set curr_hash {}
set tmp_output ""

db_foreach sql $sql {

	im_report_display_footer \
	    -output_format $output_format \
	    -group_def $report_def \
	    -footer_array_list $footer_array_list \
	    -last_value_array_list $last_value_list \
	    -level_of_detail $level_of_detail \
	    -row_class $class \
	    -cell_class $class

	im_report_update_counters -counters $counters
	
	set last_value_list [im_report_render_header \
	    -output_format $output_format \
	    -group_def $report_def \
	    -last_value_array_list $last_value_list \
	    -level_of_detail $level_of_detail \
	    -row_class $class \
	    -cell_class $class
        ]

        set footer_array_list [im_report_render_footer \
	    -output_format $output_format \
	    -group_def $report_def \
	    -last_value_array_list $last_value_list \
	    -level_of_detail $level_of_detail \
	    -row_class $class \
	    -cell_class $class
        ]
}

im_report_display_footer \
    -output_format $output_format \
    -group_def $report_def \
    -footer_array_list $footer_array_list \
    -last_value_array_list $last_value_list \
    -level_of_detail $level_of_detail \
    -display_all_footers_p 1 \
    -row_class $class \
    -cell_class $class

im_report_render_row \
    -output_format $output_format \
    -row $footer0 \
    -row_class $class \
    -cell_class $class \
    -upvar_level 1

switch $output_format {

    html  {ns_write "</table>\n[im_footer]\n"}
}

ns_write [append reimbursement_output_table "<br><br><br>"]


