
class Timeline
  def self.page(page)
    from      = (page-1)*10
    to        = (page)*10
    post_ids = redis.lrange("timeline", from, to)
    post_ids.map {|post_id| Post.new(post_id)}
  end
end

class Model
  def initialize(id)
    @id = id
  end
  
  def ==(other)
    @id.to_s == other.id.to_s
  end
  
  attr_reader :id
  
  def self.property(type)
    #Module.name gives the class name
    #self.name also works but within self.property it is redundant
    klass = name.downcase
    self.class_eval <<-RUBY
      def #{type}
        _#{type}
      end
      
      def _#{type}
        redis.hget("#{klass}:" + id.to_s, "#{type}")
      end
      
      def #{type}=(val)
        redis.hset("#{klass}:" + id.to_s, "#{type}", val)
      end
    RUBY
  end
end  

class User < Model
  def self.find_by_username(username)
    if id = redis.get("user:username:#{username}")
      User.new(id)
    end
  end
  
  def self.find_by_id(id)
    if redis.hexists("user:#{id}", :username)
      User.new(id)
    end
  end
  
  def self.create(username, password)
    user_id = redis.incr("user:uid")
    salt = User.new_salt

    redis.hmset("user:#{user_id}", "username", username, "salt", salt, "hashed_password", hash_pw(salt, password))
    redis.set("user:username:#{username}", user_id)

    redis.lpush("users", user_id)
    User.new(user_id)
  end
  
  def self.new_users
    redis.lrange("users", 0, 10).map do |user_id|
      User.new(user_id)
    end
  end
  
  def self.new_salt
    arr = %w(a b c d e f)
    (0..6).to_a.map{ arr[rand(6)] }.join
  end
  
  def self.hash_pw(salt, password)
    Digest::MD5.hexdigest(salt + password)
  end
  
  property :username
  property :salt
  property :hashed_password
  
  def posts(page=1)
    from, to = (page-1)*10, page*10
    redis.lrange("user:id:#{id}:posts", from, to).map do |post_id|
      Post.new(post_id)
    end
  end
  
  def timeline(page=1)
    from, to = (page-1)*10, page*10
    redis.lrange("user:id:#{id}:timeline", from, to).map do |post_id|
      Post.new(post_id)
    end
  end
  
  def mentions(page=1)
    from, to = (page-1)*10, page*10
    redis.lrange("user:id:#{id}:mentions", from, to).map do |post_id|
      Post.new(post_id)
    end
  end
  
  def add_post(post)
    redis.lpush("user:id:#{id}:posts", post.id)
    redis.lpush("user:id:#{id}:timeline", post.id)
  end
  
  def add_timeline_post(post)
    redis.lpush("user:id:#{id}:timeline", post.id)
  end
  
  def add_mention(post)
    redis.lpush("user:id:#{id}:mentions", post.id)
  end
  
  def follow(user)
    return if user == self
    redis.sadd("user:id:#{id}:followees", user.id)
    user.add_follower(self)
  end
  
  def stop_following(user)
    redis.srem("user:id:#{id}:followees", user.id)
    user.remove_follower(self)
  end
  
  def following?(user)
    redis.sismember("user:id:#{id}:followees", user.id)
  end
  
  def followers
    redis.smembers("user:id:#{id}:followers").map do |user_id|
      User.new(user_id)
    end
  end
  
  def followees
    redis.smembers("user:id:#{id}:followees").map do |user_id|
      User.new(user_id)
    end
  end
  
  protected
  
  def add_follower(user)
    redis.sadd("user:id:#{id}:followers", user.id)
  end
  
  def remove_follower(user)
    redis.srem("user:id:#{id}:followers", user.id)
  end
end
  
class Post < Model
  def self.create(user, content)
    post_id = redis.incr("post:uid")
    post = Post.new(post_id)
    
    post.content = content
    post.user_id = user.id
    post.created_at = Time.now.to_s
    post.user.add_post(post)
    
    redis.lpush("timeline", post_id)
    
    post.user.followers.each do |follower|
      follower.add_timeline_post(post)
    end
    
    content.scan(/@\w+/).each do |mention|
      if user = User.find_by_username(mention[1..-1])
        user.add_mention(post)
      end
    end
  end
  
  property :content
  property :user_id
  property :created_at
  
  def created_at
    Time.parse(_created_at)
  end
  
  def user
    User.new(user_id)
  end
end









