# /packages/intranet-reporting-finance/www/finance-expenses-reimbursement.tcl
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
    { end_date "2011-01-01" }
    { level_of_detail 4 }
    { output_format "html" }
    { group_style "emp_cust_proj" }
    project_id:integer,optional
    company_id:integer,optional
    user_id:integer,optional,multiple    
    intranet_expense_payment_type_id:integer,optional
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

set page_title "Projects Expenses"
set context_bar [im_context_bar $page_title]
set context ""

set help_text "
<strong>Expenses:</strong><br>

This report shows all expenses in the system in a given period,
grouped by Group Style.
"


# ------------------------------------------------------------
# Defaults

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

# Maxlevel is 4. Normalize in order to show the right drop-down element
if {$level_of_detail > 4} { set level_of_detail 4 }


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


set company_url "/intranet/companies/view?company_id="
set project_url "/intranet/projects/view?project_id="
set invoice_url "/intranet-invoices/view?invoice_id="
set expense_url "/intranet-expenses/new?form_mode=display&expense_id="
set user_url "/intranet/users/view?user_id="

set this_url [export_vars -base "/intranet-reporting-finance/finance-expenses" {start_date end_date project_id} ]


# ------------------------------------------------------------
# Conditional SQL Where-Clause
#

set criteria [list]

if {[info exists company_id] && "" != $company_id} {
    lappend criteria "pcust.company_id = :company_id"
} else {
	set company_id ""
}

# Select project & subprojects
if {[info exists project_id] && "" != $project_id } {
    lappend criteria "p.project_id in (
	select
		p.project_id
	from
		im_projects p,
		im_projects parent_p
	where
		parent_p.project_id = :project_id
		and p.tree_sortkey between parent_p.tree_sortkey and tree_right(parent_p.tree_sortkey)
		and p.project_status_id not in ([im_project_status_deleted])
    )"
} else {
	set project_id ""
}

if {[info exists user_id] && "" != $user_id} {
    lappend criteria "u.user_id in ([join $user_id ","])"
} else {
        set user_id ""
}

if {[info exists intranet_expense_payment_type_id] && "" != $intranet_expense_payment_type_id} {
    	lappend criteria "e.expense_payment_type_id = :intranet_expense_payment_type_id"
} else {
        set intranet_expense_payment_type_id ""
}

set where_clause [join $criteria " and\n            "]
if { ![empty_string_p $where_clause] } {
    set where_clause " and $where_clause"
}

# ------------------------------------------------------------
# Define the report - SQL, counters, headers and footers
#

set inner_sql "
	select
	        c.*,
	        round((c.paid_amount *
		 im_exchange_rate(c.effective_date::date, c.currency, '[parameter::get -package_id [apm_package_id_from_key intranet-cost] -parameter "DefaultCurrency" -default 'EUR']')) :: numeric
		 , 2) as paid_amount_converted,
 	        round((c.amount *
		 im_exchange_rate(c.effective_date::date, c.currency, '[parameter::get -package_id [apm_package_id_from_key intranet-cost] -parameter "DefaultCurrency" -default 'EUR']')) :: numeric
		 , 2) as amount_converted,
                round(((c.amount * (1 + c.vat / 100)) *
                 im_exchange_rate(c.effective_date::date, c.currency, '[parameter::get -package_id [apm_package_id_from_key intranet-cost] -parameter "DefaultCurrency" -default 'EUR']')) :: numeric
                 , 2) as expense_amount_converted,
	        r.project_id as project_project_id, 
		round(reimbursable :: numeric, 2) as reimbursable
	from
	        im_costs c
		LEFT OUTER JOIN (
			select	r.object_id_one as project_id,
				r.object_id_two as cost_id,
				e.reimbursable
			from	acs_rels r,
				im_expenses e
			where	r.object_id_two = e.expense_id
		    UNION
			select	c.project_id,
				c.cost_id,
				0 as reimbursable
			from	im_costs c
			where	c.cost_type_id in (
					[im_cost_type_expense_item],
					[im_cost_type_expense_bundle]
				)
		) r on (c.cost_id = r.cost_id)
	where
	        c.cost_type_id in (
			[im_cost_type_expense_item],
			[im_cost_type_expense_bundle]
		)
	        and c.effective_date >= to_date(:start_date, 'YYYY-MM-DD')
	        and c.effective_date < to_date(:end_date, 'YYYY-MM-DD')
	        and c.effective_date::date < to_date(:end_date, 'YYYY-MM-DD')
"


switch $group_style {
    cust_proj_emp { 
	set order_by_clause "
		pcust.company_name,
		p.project_name,
		employee_name
        "
    }
    cust_proj_exptype {
	set order_by_clause "
		pcust.company_name,
		p.project_name,
		expense_type
        "
    }
    emp_cust_proj { 
	set order_by_clause "
		employee_name,
		p.company_id,
		p.project_name
        "
    }
}


set def_curr [parameter::get -package_id [apm_package_id_from_key intranet-cost] -parameter "DefaultCurrency" -default 'EUR']

#	-- to_char(((cc.amount_converted * c.vat/100) + c.amount)*e.reimbursable/100,:cur_format) as amount_reimbursable_converted,

set sql "
select
	cc.*,
	e.*,
	round(c.amount,2) as amount, 
	im_category_from_id(e.expense_type_id) as expense_type,
	im_category_from_id(e.expense_payment_type_id) as expense_payment_type,
	to_char(cc.effective_date, :date_format) as effective_date_formatted,
	to_char(cc.effective_date, 'YYMM')::integer * cc.customer_id as effective_month,
	to_char(c.vat, '990') as vat_formatted,
	to_char(c.amount, :cur_format) as amount_formatted,
	to_char((c.amount * c.vat/100) + c.amount, :cur_format) as amount_incl_vat_formatted,
	to_char(((c.amount * c.vat/100) + c.amount)*e.reimbursable/100,:cur_format) as amount_reimbursable,
	to_char(cc.expense_amount_converted *e.reimbursable/100, :cur_format) as amount_reimbursable_converted,
	to_char(cc.amount_converted, :cur_format) as amount_converted_formatted,
	to_char(o.creation_date, :date_format) as cost_creation_date_formatted,
	cust.company_path as customer_nr,
	cust.company_name as customer_name,
	pcust.company_id as project_customer_id,
	pcust.company_name as project_customer_name,
	u.user_id as employee_id,
	im_name_from_user_id(u.user_id) as employee_name,
	p.project_name,
	p.project_nr,
	p.project_id,
	p.end_date::date as project_end_date,
	1.0 * p.project_id * u.user_id as pu_id
from
	im_costs c,
	acs_objects o,
	im_expenses e,
	($inner_sql) cc
	LEFT OUTER JOIN im_projects p on (cc.project_project_id = p.project_id)
	LEFT OUTER JOIN im_companies cust on (cc.customer_id = cust.company_id)
	LEFT OUTER JOIN im_companies pcust on (p.company_id = pcust.company_id)
	LEFT OUTER JOIN cc_users u on (cc.provider_id = u.user_id)
where
	cc.cost_id = c.cost_id
	and cc.cost_id = e.expense_id
	and cc.cost_id = o.object_id
	$where_clause
order by
	$order_by_clause
"


set total 0
set employee_subtotal 0
set employee_subtotal_vat_reimburse 0


switch $group_style {

    cust_proj_emp {

	# -------------------------------------------------------------------------------------------------
	set report_def [list \
		group_by project_customer_id \
		header {
			"\#colspan=12 <a href=$this_url&customer_id=$project_customer_id&level_of_detail=4
			target=_blank><img src=/intranet/images/plus_9.gif width=9 height=9 border=0></a>
			<b><a href=$company_url$project_customer_id>$project_customer_name</a></b>"
		} \
		content [list \
			group_by project_id \
			header {
				""
				"\#colspan=9 <a href=$this_url&project_id=$project_id&level_of_detail=4
				target=_blank><img src=/intranet/images/plus_9.gif width=9 height=9 border=0></a>
				<b><a href=$project_url$project_id>$project_name</a></b>"
				""
				""
			} \
			content [list \
				group_by pu_id \
				header {
					""
					""
					"\#colspan=8 <a href=$this_url&employee_id=$employee_id&level_of_detail=4
					target=_blank><img src=/intranet/images/plus_9.gif width=9 height=9 border=0></a>
					<b><a href=$user_url$employee_id>$employee_name</a></b>"
					""
					""
				} \
				content [list \
					header {
						""
						""
						""
						"<a href=$expense_url$cost_id><nobr>$effective_date_formatted</nobr></a>"
						"$expense_type"
						"$external_company_name"
						"$expense_payment_type"
						"$vat_formatted"
						"<nobr>$amount_formatted $currency</nobr>"
						"<nobr>$amount_converted_formatted $default_currency</nobr>"
                                                "<nobr>$amount_incl_vat_formatted $currency</nobr>"
						"$billable_p"
						"$note"
					} \
					content {} \
				] \
				footer {
					"\#colspan=9"
					"\#colspan=3 <nobr><i>$employee_subtotal</i></nobr>"
				} \
			] \
			footer {
				"\#colspan=9"
				"\#colspan=3 <nobr><b>$project_subtotal</b></nobr>"
			} \
		] \
		footer {  } \
	]
		
	# Global header/footer
	set header0 {"Cust" "Proj" "Emp" "Expense<br>Date" "Type" "Ext<br>Company" "Pay<br>Type" "%VAT" "Amount" "Amount<br>Conv" "Amount incl. VAT" "Bill<br>able?" "Note"}
	set footer0 { }

	set project_subtotal_counter [list \
	        pretty_name "Invoice Amount" \
	        var project_subtotal \
	        reset "\$customer_id+\$project_id" \
	        expr "\$amount+0" \
	]
	
	set employee_subtotal_counter [list \
	        pretty_name "Invoice Amount" \
	        var employee_subtotal \
	        reset "\$customer_id+\$project_id+\$employee_id" \
	        expr "\$amount+0" \
	]
	set project_grand_total_counter [list \
	        pretty_name "Invoice Amount" \
	        var project_total \
	        reset 0 \
	        expr "\$amount+0" \
	]
	
	set counters [list \
		$project_subtotal_counter \
		$employee_subtotal_counter \
		$project_grand_total_counter \
	]

    }


    cust_proj_exptype {

	# -------------------------------------------------------------------------------------------------
	set report_def [list \
		group_by project_customer_id \
		header {
			"\#colspan=13 <a href=$this_url&customer_id=$project_customer_id&level_of_detail=4
			target=_blank><img src=/intranet/images/plus_9.gif width=9 height=9 border=0></a>
			<b><a href=$company_url$project_customer_id>$project_customer_name</a></b>"
		} \
		content [list \
			group_by project_id \
			header {
				""
				"\#colspan=10 <a href=$this_url&project_id=$project_id&level_of_detail=4
				target=_blank><img src=/intranet/images/plus_9.gif width=9 height=9 border=0></a>
				<b><a href=$project_url$project_id>$project_name</a></b>"
				""
				""
			} \
			content [list \
				group_by expense_type \
				header {
					""
					""
					"\#colspan=9 $expense_type"
					""
					""
				} \
				content [list \
					header {
						""
						""
						""
						"<a href=$expense_url$cost_id><nobr>$effective_date_formatted</nobr></a>"
						"<nobr>$cost_creation_date_formatted</nobr>"
						"<a href=$user_url$employee_id>$employee_name</a>"
						"$external_company_name"
						"$expense_payment_type"
						"$vat_formatted"
						"<nobr>$amount_formatted $currency</nobr>"
						"<nobr>$amount_converted_formatted $default_currency</nobr>"
                                                "<nobr>$amount_incl_vat_formatted $currency</nobr>"
						"$billable_p"
						"$note"
					} \
					content {} \
				] \
				footer {
					"\#colspan=10"
					"\#colspan=3 <nobr><i>$exptype_subtotal</i></nobr>"
				} \
			] \
			footer {
				"\#colspan=10"
				"\#colspan=3 <nobr><b>$project_subtotal</b></nobr>"
			} \
		] \
		footer {  } \
	]
		
	# Global header/footer
	set header0 {"Cust" "Proj" "Type" "Expense<br>Date" "Enter<br>Date" "Emp" "Ext<br>Company" "Pay<br>Type" "%VAT" "Amount" "Amount<br>Conv" "Amount incl. VAT" "Bill<br>able?" "Note"}
	set footer0 { }
	
	set project_subtotal_counter [list \
	        pretty_name "Invoice Amount" \
	        var project_subtotal \
	        reset \$project_id \
	        expr "\$amount+0" \
	]
	
	set exptype_subtotal_counter [list \
	        pretty_name "Invoice Amount" \
	        var exptype_subtotal \
	        reset "\$project_id+\$expense_type_id" \
	        expr "\$amount+0" \
	]
	set project_grand_total_counter [list \
	        pretty_name "Invoice Amount" \
	        var project_total \
	        reset 0 \
	        expr "\$amount+0" \
	]
	
	set counters [list \
		$project_subtotal_counter \
		$exptype_subtotal_counter \
		$project_grand_total_counter \
	]


    }

    emp_cust_proj {

	# -------------------------------------------------------------------------------------------------
	set report_def [list \
		group_by employee_id \
		header {
			"\#colspan=8 <a href=$this_url&employee_id=$employee_id&level_of_detail=4
			target=_blank><img src=/intranet/images/plus_9.gif width=9 height=9 border=0></a>
			<b><a href=$user_url$employee_id>$employee_name</a></b>"
		} \
		content [list \
			group_by project_customer_id \
			header {
				""
				"\#colspan=6 <a href=$this_url&customer_id=$project_customer_id&level_of_detail=4
				target=_blank><img src=/intranet/images/plus_9.gif width=9 height=9 border=0></a>
				<b><a href=$company_url$project_customer_id>$project_customer_name</a></b>"
				""
				""
			} \
			content [list \
				group_by project_id \
				header {
					""
					""
					"\#colspan=6 <a href=$this_url&project_id=$project_id&level_of_detail=4
					target=_blank><img src=/intranet/images/plus_9.gif width=9 height=9 border=0></a>
					<b><a href=$project_url$project_id>$project_name</a></b>"
					""
					""
				} \
				content [list \
					header {
						""
						""
						""
						"<a href=$expense_url$cost_id><nobr>$effective_date_formatted</nobr></a>"
						"$expense_type"
						"$external_company_name"
						"$expense_payment_type"
                                                "<nobr>$amount_incl_vat_formatted $currency</nobr>"
						"$reimbursable"
					        "$amount_reimbursable $currency"
                                                "$amount_reimbursable_converted $default_currency"
						"$note"
					} \
					content {} \
				] \
				footer {
					"\#colspan=6"
					"\#colspan=3 <nobr>Project:<br> <i>$project_subtotal</i></nobr><br><br>"
				} \
			] \
			footer {
				"\#colspan=6"
				"\#colspan=3 <nobr>Customer:<br> <b>$customer_subtotal</b></nobr>"
			} \
		] \
		footer {  
			"\#colspan=6"
			"\#colspan=4 <br><br>-----<br><nobr>Employee:<br> <b>$employee_subtotal</b></nobr>"
			"\#colspan=3 <br><br>-----<br><nobr>Employee:<br> <b>$employee_subtotal_vat_reimburse</b></nobr>"
		} \
	]

	# Global header/footer
	set header0 {"Emp" "Cust" "Proj" "Expense<br>Date" "Type" "Ext<br>Company" \
			 "Pay<br>Type" "Amount incl. VAT" "% Reimbursable" "Amount<br>Reimbursable" "Amount Reimbursable<br>converted" "Note"}
	set footer0 { }
	
        set employee_subtotal_vat_reimburse_counter [list \
                pretty_name "Invoice Amount" \
                var employee_subtotal_vat_reimburse \
                reset "\$employee_id" \
                expr "\$amount_reimbursable_converted+0" \
        ]

	set employee_subtotal_counter [list \
	        pretty_name "Invoice Amount" \
	        var employee_subtotal \
	        reset "\$employee_id" \
	        expr "\$amount+0" \
	]
	set customer_subtotal_counter [list \
	        pretty_name "Invoice Amount" \
	        var customer_subtotal \
	        reset "\$employee_id+\$project_customer_id" \
	        expr "\$amount+0" \
	]
	set project_subtotal_counter [list \
	        pretty_name "Invoice Amount" \
	        var project_subtotal \
	        reset "\$employee_id+\$project_customer_id+\$project_id" \
	        expr "\$amount+0" \
	]
	set counters [list \
		$employee_subtotal_vat_reimburse_counter \
		$project_subtotal_counter \
		$customer_subtotal_counter \
		$employee_subtotal_counter \

	]
    }
}


	



# ------------------------------------------------------------
# Constants
#

set start_years {2000 2000 2001 2001 2002 2002 2003 2003 2004 2004 2005 2005 2006 2006}
set start_months {01 Jan 02 Feb 03 Mar 04 Apr 05 May 06 Jun 07 Jul 08 Aug 09 Sep 10 Oct 11 Nov 12 Dec}
set start_weeks {01 1 02 2 03 3 04 4 05 5 06 6 07 7 08 8 09 9 10 10 11 11 12 12 13 13 14 14 15 15 16 16 17 17 18 18 19 19 20 20 21 21 22 22 23 23 24 24 25 25 26 26 27 27 28 28 29 29 30 30 31 31 32 32 33 33 34 34 35 35 36 36 37 37 38 38 39 39 40 40 41 41 42 42 43 43 44 44 45 45 46 46 47 47 48 48 49 49 50 50 51 51 52 52}
set start_days {01 1 02 2 03 3 04 4 05 5 06 6 07 7 08 8 09 9 10 10 11 11 12 12 13 13 14 14 15 15 16 16 17 17 18 18 19 19 20 20 21 21 22 22 23 23 24 24 25 25 26 26 27 27 28 28 29 29 30 30 31 31}
set levels {1 "User" 2 "User+Client" 3 "User-Client-Project" 4 "All Details"}
# set group_style_options {"cust_proj_emp" "Customer - Project - Employee" "cust_proj_exptype" "Customer - Project - Expense Type" "emp_cust_proj" "Employee - Customer - Project"}
set group_style_options {"emp_cust_proj" "Employee - Customer - Project"}

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
                [export_form_vars customer_id]
		<table border=0 cellspacing=1 cellpadding=1>
		<tr>
		  <td class=form-label>Level of Details</td>
		  <td class=form-widget>
		    [im_select -translate_p 0 level_of_detail $levels $level_of_detail]
		  </td>
		</tr>
<!--
		<tr>
		  <td class=form-label>Group Style</td>
		  <td class=form-widget>
		    [im_select -translate_p 0 group_style $group_style_options $group_style]
		  </td>
		</tr>
-->
		<tr>
		  <td class=form-label>Customer</td>
		  <td class=form-widget>
			[im_company_select -include_empty_name [lang::message::lookup "" intranet-core.All "All"] company_id $company_id]
		  </td>
		</tr>
                <tr>
                  <td class=form-label>Project</td>
                  <td class=form-widget>
			[im_project_select -include_empty_p 1 -include_empty_name [lang::message::lookup "" intranet-core.All "All"] project_id $project_id]	
                  </td>
                </tr>
                <tr>
                  <td class=form-label>User</td>
                  <td class=form-widget>
                        [im_employee_select_multiple user_id $user_id 6 multiple]
                  </td>
                </tr>
                <tr>
                  <td class=form-label>Expense Type</td>
                  <td class=form-widget>
                        [im_category_select -include_empty_p 1 "Intranet Expense Payment Type" intranet_expense_payment_type_id $intranet_expense_payment_type_id]
                  </td>
                </tr>
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
                  <td class=form-label>Format</td>
                  <td class=form-widget>
                    [im_report_output_format_select output_format "" $output_format]
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

ns_log Notice "intranet-reporting-finance/finance-expenses-reimbursement.tcl: sql=\n$sql"

set first_loop_p 1
set currency list
array set curr_hash {}
set tmp_output ""


db_foreach sql $sql {

	if {[string length $expense_payment_type] > $expense_payment_type_length} {
	    set expense_payment_type "[string range $expense_payment_type 0 $expense_payment_type_length] ..."
	}

	if {[string length $note] > $note_length} {
	    set note "[string range $note 0 $note_length] ..."
	}

	if {"" == $project_id} {
	    set project_id 0
	    set project_name [lang::message::lookup "" intranet-reporting.No_project "Undefined Project"]
	}

	if {"" == $project_customer_id} {
	    set project_customer_id 0
	    set project_customer_name [lang::message::lookup "" intranet-reporting.No_customer "Undefined Customer"]
	}

	if {"" == $amount_converted} {
	    set amount_converted "<font color=red>exchange rate missing</font>"
	}

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

	# -- create summaries for each currency  
	# first record? 
	if { 1 == $first_loop_p } {
    		lappend currency_list $currency
		set curr_idx 0
		set first_loop_p 0 
	} else { 
		set curr_idx [lsearch $currency_list $currency]
		if { -1 == $curr_idx } {
	                lappend currency_list $currency
	                set curr_idx [lsearch $currency_list $currency]
		}
	}

	append tmp_output "Employee_id $employee_id, Currency: $currency<br>"

	if { [info exists curr_hash($employee_id,$curr_idx) ] } {
		# ad_return_complaint 1 "$employee_id $curr_idx $curr_hash($employee_id,$curr_idx)"
		set curr_hash($employee_id,$curr_idx) [expr $curr_hash($employee_id,$curr_idx) + $amount_reimbursable]
	} else {
                set curr_hash($employee_id,$curr_idx) $amount_reimbursable
	}
}

set reimbursement_output_table "-----------------------------------------------------------------------------------<br><h2>&nbsp;&nbsp;&nbsp;&nbsp;Reimbursement Employee/Currency:</h2>"
set bak_key "" 

foreach key [array names curr_hash] { 
	#get current value with $curr_hash($key)
	if {$bak_key == $key} {
		set employee_id ""	
	} else {
		set employee_id [string range $key 0 [expr [string first "," $key]-1]]  
	}
	set employee_name [im_name_from_user_id $employee_id]
	append reimbursement_output_table "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;$employee_name: $curr_hash($key)&nbsp;[lindex $currency_list [string range $key [expr [string first "," $key]+1] [string length $key]]]<br>" 
	set bak_key $key
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

