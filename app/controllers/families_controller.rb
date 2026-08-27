# frozen_string_literal: true

class FamiliesController < ApplicationController
  before_action :authenticate_user!
  # #new doubles as the landing page for users without the plan (upgrade CTA
  # instead of the create form). #destroy stays open so a lapsed owner can
  # dissolve the family. #index/#show stay open so members of a lapsed family
  # (whose per-user family_feature_available? is false) can still reach them.
  before_action :ensure_family_feature_available!, except: %i[index show new destroy]
  before_action :set_family, only: %i[show edit update destroy]

  def index
    @families = current_user.families.includes(:family_memberships).order(:name)
  end

  def show
    authorize @family

    if @family.lapsed?
      @is_owner = current_user.owner_of?(@family)
      @family_upgrade_url = helpers.family_upgrade_url(utm_medium: 'family', utm_content: 'renew_family') if @is_owner
      render :lapsed and return
    end

    @members = @family.members.order(:email)
    @pending_invitations = @family.active_invitations.order(:created_at)

    @member_count = @family.member_count
    @can_invite = @family.can_add_members?
    @pending_requests = current_user.sent_location_requests.pending
                                    .where('expires_at > ?', Time.current)
                                    .where(family_id: @family.id)
                                    .index_by(&:target_user_id)

    @memberships_by_user = @family.family_memberships.index_by(&:user_id)
    @member_locations = @memberships_by_user.values.filter_map(&:latest_location)
  end

  def new
    @family = Family.new
    @can_create_family = FamilyPolicy.new(current_user, @family).create?
    return if @can_create_family

    @family_upgrade_url = helpers.family_upgrade_url(utm_medium: 'family', utm_content: 'create_family')
  end

  def create
    @family = Family.new(family_params)
    authorize @family

    service = Families::Create.new(
      user: current_user,
      name: family_params[:name]
    )

    if service.call
      redirect_to family_path(service.family), notice: I18n.t('controllers.families.family_created_successfully')
    else
      @family = Family.new(family_params)

      if service.errors.any?
        service.errors.each do |error|
          @family.errors.add(error.attribute, error.message)
        end
      end

      @family.errors.add(:base, service.error_message) if service.error_message.present?

      flash.now[:alert] = service.error_message || I18n.t('controllers.families.failed_to_create_family')
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @family
  end

  def update
    authorize @family

    if @family.update(family_params)
      redirect_to family_path(@family), notice: I18n.t('controllers.families.family_updated_successfully')
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @family

    if @family.members.count > 1
      redirect_to family_path(@family),
                  alert: I18n.t('controllers.families.cannot_delete_family_with_members_remove_all_members_first')
    else
      @family.destroy
      redirect_to families_path, notice: I18n.t('controllers.families.family_deleted_successfully')
    end
  end

  private

  def set_family
    @family = current_user.families.find(params[:id])
  end

  def family_params
    params.require(:family).permit(:name)
  end
end
