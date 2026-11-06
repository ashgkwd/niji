# The leak that started niji, kept so it stays reproducible: the alt text of
# every avatar carried the person's name and email into the page, on every
# public review. The fixed helper has an empty alt, because the name is
# printed beside the picture.
module AvatarsHelper
  def avatar_tag(user)
    image_tag "avatar.png", alt: user.name_with_email
  end
end
