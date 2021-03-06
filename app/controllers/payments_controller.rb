class PaymentsController < ApplicationController
  before_action :authenticate_user!
  before_filter :authenticate_admin!
  
  skip_before_filter :authenticate_user!, only: [:payment_notify]
  skip_before_filter :authenticate_admin!, only: [:payment_notify]
  skip_before_filter :verify_authenticity_token, only: [:payment_notify]

  def index
    @monthlys = User.pro_only.monthly
    @yearlys =  User.pro_only.yearly

    @monthly_recurring = 0
    @monthlys.each do |user|
      @monthly_recurring += user.payments.last.amount
    end

    @annual_recurring = 0
    @yearlys.each do |user|
      @annual_recurring += user.payments.last.amount
    end

    @mrr = @monthly_recurring.to_i + (@annual_recurring.to_i/12)

    @payments = Payment.includes(:user).all.order("date DESC, id DESC")
    params[:per] ||= 100
    @paginated_payments = Kaminari.paginate_array(@payments).page(params[:page]).per(params[:per])
  end

  def new
    @payment = Payment.new
  end

  def create

    if params[:user_email].present?
      user = User.find_by(email: params[:user_email].downcase)
      params[:payment][:user_id] = user.id if user.present?
    end

    @payment = Payment.create(payment_params)

    if @payment.save
      if user.present? && params["send_thanks"] == 1
        UserMailer.thanks_for_paying(user).deliver_later
        flash[:notice] = "Payment added successfully & thanks was sent!"
      else
        flash[:notice] = "Payment added successfully!"
      end
      user.update(user_params) if user.present? && user_params[:plan].present?
      redirect_to payments_path
    else
      render 'new'
    end
  end

  def edit
    @payment = Payment.find(params[:id])
  end

  def update
    @payment = Payment.find(params[:id])
    if params[:user_email].present?
      user = User.find_by(email: params[:user_email].downcase)
      params[:payment][:user_id] = user.id if user.present?
    end

    if @payment.update(payment_params)
      user.update(user_params) if user.present? && user_params[:plan].present?
      flash[:notice] = "Payment successfully updated!"
      redirect_to payments_path
    else
      render 'edit'
    end
  end

  def destroy
    @payment = Payment.find(params[:id])
    @payment.destroy
    flash[:notice] = 'Payment deleted successfully.'
    redirect_to payments_path
  end

  def payment_notify
    plan = 'Free'

    # check for GUMROAD
    if params[:email].present? && params[:seller_id] == ENV['GUMROAD_SELLER_ID'] && params[:product_id] == ENV['GUMROAD_PRODUCT_ID']
      user = User.find_by(gumroad_id: params[:purchaser_id])
      user = User.find_by(email: params[:email].downcase) if user.blank?
      paid = params[:price].to_f / 100
      if params[:recurrence].present?
        frequency = params[:recurrence].titleize
      else
        frequency = paid.to_i > 10 ? 'Yearly' : 'Monthly'
      end
      if user.present? && user.payments.count > 0 && Payment.where(user_id: user.id).last.date.to_date === Time.now.to_date
        # duplicate, don't send
      elsif user.present?
        payment = Payment.create(user_id: user.id, comments: "Gumroad #{frequency} from #{params[:email]}", date: "#{Time.now.strftime("%Y-%m-%d")}", amount: paid )
        begin        
          UserMailer.thanks_for_paying(user).deliver_later if user.payments.count == 1
        rescue StandardError => e
          Rails.logger.warn("Error sending Gumroad thanks_for_paying email email to #{user.email}: #{e}")
        end          
      end
      plan = "PRO #{frequency} Gumroad"
      gumroad_id = params[:purchaser_id]

      begin
        UserMailer.no_user_here(params[:email], 'Gumroad', params[:purchaser_id]).deliver_later if user.blank?
      rescue StandardError => e
        Rails.logger.warn("Error sending no_user_her email to #{params[:email]}: #{e}")
      end

    # check for Paypal
    elsif params[:item_name].present? && params[:item_name].include?('Dabble Me') && params[:payment_status].present? && params[:payment_status] == "Completed" && params[:receiver_id] == ENV['PAYPAL_SELLER_ID']

      user_key = params[:item_name].gsub('Dabble Me PRO for ','') if params[:item_name].present?
      user = User.find_by(user_key: user_key)

      paid = params[:mc_gross]
      frequency = paid.to_i > 10 ? 'Yearly' : 'Monthly'

      if user.present? && user.payments.count > 0 && Payment.where(user_id: user.id).last.date.to_date === Time.now.to_date
        # duplicate webhook, don't save
      elsif user.present?
        payment = Payment.create(user_id: user.id, comments: "Paypal #{frequency} from #{params[:payer_email]}", date: "#{Time.now.strftime("%Y-%m-%d")}", amount: paid )
        begin
          UserMailer.thanks_for_paying(user).deliver_later if user.payments.count == 1
        rescue StandardError => e
          Rails.logger.warn("Error sending Paypal thanks_for_paying email to #{user.email}: #{e}")
        end
      end
      plan = "PRO #{frequency} PayPal"
      gumroad_id = user.gumroad_id if user.present?
      UserMailer.no_user_here(params[:payer_email], 'PayPal', nil).deliver_later if user.blank?
    end

    user.update(plan: plan, gumroad_id: gumroad_id) if user.present?
    head :ok, content_type: 'text/html'
  end

  private

  def payment_params
    params.require(:payment).permit(:amount, :date, :user_id,  :comments)
  end

  def user_params
    params.permit(:plan)
  end 
end
