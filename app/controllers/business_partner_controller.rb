# -*- encoding: utf-8 -*-
class BusinessPartnerController < ApplicationController
  def index
    list
    render :action => 'list'
  end

  # GETs should be safe (see http://www.w3.org/2001/tag/doc/whenToUseGet.html)
#  verify :method => :post, :only => [ :destroy, :create, :update ],
#         :redirect_to => { :action => :list }

  def set_conditions
    session[:business_partner_search] = {
      :sales_code => params[:sales_code],
      :business_partner_name => params[:business_partner_name],
      :self_flg => params[:self_flg],
      }
  end

  def _make_conditions
    param = []
    incl = []
    sql = "business_partners.deleted = 0"

    if !(sales_code = session[:business_partner_search][:sales_code]).blank?
      sql += " and (business_partner_code = ? or sales_code = ?)"
      param << sales_code << sales_code
    end

    if !(business_partner_name = session[:business_partner_search][:business_partner_name]).blank?
      sql += " and (business_partner_name like ? or business_partner_name_kana like ?)"
      param << "%#{business_partner_name}%" << "%#{business_partner_name}%"
    end
    return [param.unshift(sql), incl]
  end

  def make_conditions
    cond, incl = _make_conditions

    if !(session[:business_partner_search][:self_flg]).blank?
      cond[0] += " and self_flg = 1"
    end

    #return {:conditions => param.unshift(sql), :include => include, :per_page => current_user.per_page}
    return [cond, incl]
  end

  def list
    session[:business_partner_search] ||= {}
    incl = []
    if params[:search_button]
      set_conditions
    elsif params[:clear_button]
      session[:business_partner_search] = {}
    end

    cond, incl = make_conditions
    #@business_partner_pages, @business_partners = paginate(:business_partners, cond)
    @business_partners = BusinessPartner.includes(incl).where(cond).order("updated_at desc").page(params[:page]).per(current_user.per_page)
  end

  def show
    @business_partner = BusinessPartner.find(params[:id])
    @bp_pics = BpPic.find(:all, :conditions => ["deleted = 0 and business_partner_id = ?", params[:id]])
    @businesses = Business.find(:all, :conditions => ["deleted = 0 and eubp_id = ?", @business_partner], :order => "id desc", :limit => 50)
    @biz_offers = BizOffer.find(:all, :conditions => ["deleted = 0 and business_partner_id = ?", @business_partner], :order => "id desc", :limit => 50)
    @bp_members = BpMember.find(:all, :conditions => ["deleted = 0 and business_partner_id = ?", @business_partner], :order => "id desc", :limit => 50)
    @remarks = Remark.get_all('business_partners', params[:id])
  end

  def new
    @business_partner = BusinessPartner.new
    @bp_pic = BpPic.new
    @bp_pic.working_status_type = 'working'
    @bp_pic.business_partner = @business_partner
    if params[:import_mail_id]
      @business_partner.import_mail_id = params[:import_mail_id]
      @bp_pic.import_mail_id = params[:import_mail_id]
    end
    @former_bp_pic = !params[:former_bp_pic_id].blank? ? BpPic.find(params[:former_bp_pic_id]) : @bp_pic.former_bp_pic
    unless @former_bp_pic.blank? #転職の場合
      @bp_pic.bp_pic_name = @former_bp_pic.bp_pic_name
      @bp_pic.bp_pic_short_name = @former_bp_pic.bp_pic_short_name
      @bp_pic.bp_pic_name_kana = @former_bp_pic.bp_pic_name_kana
    end

  end

  def create
    @bp_pic = BpPic.new(params[:bp_pic])
    ActiveRecord::Base.transaction do

      if params[:business_partner][:id].blank?
        @business_partner = BusinessPartner.new(params[:business_partner])
        @business_partner.basic_contract_first_party_status_type ||= 'none'
        @business_partner.basic_contract_second_party_status_type ||= 'none'
        @business_partner.tag_text = Tag.normalize_tag(@business_partner.tag_text).join(" ")
      else
        # 取り込みメールからのBP・BP担当登録で、BPを登録済のものから選択した場合
        @business_partner = BusinessPartner.find(params[:business_partner][:id])
      end

      @business_partner.business_partner_name = space_trim(params[:business_partner][:business_partner_name])
      set_user_column @business_partner
      @business_partner.save!

      Tag.update_tags!('business_partners', @business_partner.id, @business_partner.tag_text)

      @bp_pic.business_partner_id = @business_partner.id
      @bp_pic.bp_pic_name = space_trim(params[:bp_pic][:bp_pic_name]).gsub(/　/," ")
      set_user_column @bp_pic
      @bp_pic.save!

      @bp_pic.update_import_mails!(current_user.login)

      BpPic.update_changed(@bp_pic.id, params[:former_bp_pic_id]) unless params[:former_bp_pic_id].blank? # 転職の登録

      if !@business_partner.import_mail_id.blank?
        import_mail = ImportMail.find(@business_partner.import_mail_id)
        import_mail.business_partner_id = @business_partner.id
        import_mail.bp_pic_id = @bp_pic.id
        set_user_column import_mail
        import_mail.save!
      end

      if params[:photo_id]
        Photo.update_bp_pic(@bp_pic.id, params[:photo_id])
      end

    end # transaction

    flash_notice = 'BusinessPartner was successfully created.'

    if popup?
      # ポップアップウィンドウの場合、共通リザルト画面を表示する
      flash.now[:notice] = flash_notice
      render 'shared/popup/result'
    elsif params[:photo_id]
      # 名刺紐付けの場合、名刺取込一覧画面を表示する
      flash.now[:notice] = flash_notice
      _redirect_or_back_to :controller => :photos, :action => :index
    else
      # ポップアップウィンドウでなければ通常の画面遷移
      flash[:notice] = flash_notice
      redirect_to :controller => :business_partner, :action => :show, :id => @business_partner.id
    end
  rescue ActiveRecord::RecordInvalid
    render :action => 'new'
  end

  def edit
    @business_partner = BusinessPartner.find(params[:id])
  end

  def update
    ActiveRecord::Base.transaction do
      @business_partner = BusinessPartner.find(params[:id], :conditions =>["deleted = 0"])
      old_tags = @business_partner.tag_text
      @business_partner.attributes = params[:business_partner]
      @business_partner.tag_text = Tag.normalize_tag(@business_partner.tag_text).join(" ")
      if old_tags != @business_partner.tag_text
        Tag.update_tags!('business_partners', @business_partner.id, @business_partner.tag_text)
      end
      @business_partner.business_partner_name = space_trim(params[:business_partner][:business_partner_name])
      set_user_column @business_partner
      @business_partner.save!
    end
    flash[:notice] = 'BusinessPartner was successfully updated.'
    redirect_to(back_to || {:action => 'show', :id => @business_partner})
  rescue ActiveRecord::RecordInvalid
    render :action => 'edit'
  end

  def destroy
    @business_partner = BusinessPartner.find(params[:id], :conditions =>["deleted = 0"])
    @business_partner.deleted = 9
    @business_partner.deleted_at = Time.now
    set_user_column @business_partner
    @business_partner.save!

    redirect_to(back_to || {:action => 'list'})
  end

  def space_trim(bp_name)
    bp_name_list = bp_name.split(/[\s　]/)
    trimed_bp_name = ""
    bp_name_list.each do |bp_name_element|
      trimed_bp_name << bp_name_element
    end
    trimed_bp_name
  end

  def space_unify(bp_pic_name)
    bp_name_list = bp_pic_name.split(/[　]/)
    trimed_bp_name = ""
    bp_name_list.each do |bp_name_element|
      trimed_bp_name << bp_name_element
      trimed_bp_name << /\s/
    end
    trimed_bp_name
  end

  def download_csv
    send_data BusinessPartner.export_to_csv, :filename => "bpexport_#{Time.now.strftime("%Y%m%d_%H%M%S")}.csv", :type => "text/csv"
  end

  def upload_csv
    unless file = params[:csv_upload_file]
      flash[:notice] = 'ファイルを選択してください'
      redirect_to(back_to || {:action => :list})
      return
    end
    ext = File.extname(file.original_filename.to_s).downcase
    raise ValidationAbort.new("インポートするファイルは、拡張子がcsvのファイルでなければなりません") if ext != '.csv'
    BusinessPartner.import_from_csv_data(file.read, SysConfig.email_prodmode?)
    flash[:notice] = 'インポートが完了しました'
    redirect_to(back_to || {:action => :list})
  end

  def upload_google_csv
    unless file = params[:google_csv_upload_file]
      flash[:notice] = 'ファイルを選択してください'
      redirect_to(back_to || {:action => :list})
      return
    end
    ext = File.extname(file.original_filename.to_s).downcase
    raise ValidationAbort.new("インポートするファイルは、拡張子がcsvのファイルでなければなりません") if ext != '.csv'
    cnt, errors = BusinessPartner.import_google_csv_data(file.read, current_user.login, SysConfig.email_prodmode?)
    unless errors.empty?
      flash[:warning] = errors.to_s.gsub(/[\[\]]/, "") + "行目のデータが取りこめませんでした"
    else
      flash[:notice] = "全#{cnt}件のインポートが完了しました"
    end
    redirect_to(back_to || {:action => :list})
  end

  def change_star
    business_partner = BusinessPartner.find(params[:id])
    if business_partner.starred == 1
      business_partner.starred = 0
    else
      business_partner.starred = 1
    end
      set_user_column business_partner
      business_partner.save!
    render :text => business_partner.starred
  end

  # 入力支援機能の更新用メソッド
  def update_quick_input
    begin
      ActiveRecord::Base.transaction do
        @business_partner = BusinessPartner.find(params[:business_partner][:id])
        @business_partner.attributes = params[:business_partner]

        if @business_partner.sales_status_type == 'listup'
          @business_partner.sales_status_type = 'prospect'
        end
        set_user_column @business_partner
        @business_partner.save!
      end
      flash[:notice] = 'BusinessPartner was successfully updated.'

    rescue ActiveRecord::RecordInvalid
      flash[:err] = '更新に失敗しました'
    end

    redirect_to( params[:back_to] || {controller: 'bp_pic', action: 'index'})
  end
end
