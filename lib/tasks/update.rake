namespace :update do
  desc "Create placeholder data for DB"
  task :enable_templates => :environment do
    cat = Category.find(2)
    cat.update_attribute(:meta_description, 'Customize the header and footer of customer email messages')
    cat.docs.create(title: 'Customer_header', body:'<!-- -->') #unless Doc.where(title: 'customer_header').count > 0
    cat.docs.create(title: 'Customer_footer', body:'<p style="color: #666;"></p>') #unless Doc.where(title: 'customer_footer').count > 0
  end
end
