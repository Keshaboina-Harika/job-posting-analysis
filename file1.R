# Load required libraries
library(tm)  # For text preprocessing and TF-IDF
library(caret)  # For dummy variable creation
library(dplyr)  # For data manipulation
library(ggplot2)  # For visualizations (optional, if needed later)

# Load the dataset (assuming `df` is your data frame)
# Replace 'your_dataset.csv' with the actual path to your dataset
df <- read.csv("D:\\projects\\da cbp\\jobstreet.csv", stringsAsFactors = FALSE)

# Set seed for reproducibility
set.seed(123)

# Sample 1000-2000 records
sample_size <- 1500  # Choose a size between 1000 and 2000
df_sample <- df[sample(nrow(df), sample_size), ]

# Check the structure of the sampled data
#print(dim(df_sample))
#print(summary(df_sample))

# Text Preprocessing Function
preprocess_text <- function(text_column) {
  text_column <- tolower(text_column)  # Convert to lowercase
  text_column <- removePunctuation(text_column)  # Remove punctuation
  text_column <- removeNumbers(text_column)  # Remove numbers
  text_column <- removeWords(text_column, stopwords("en"))  # Remove stopwords
  text_column <- stripWhitespace(text_column)  # Remove extra whitespaces
  return(text_column)
}

# Apply preprocessing to text columns
df_sample$job_title <- preprocess_text(df_sample$job_title)
df_sample$descriptions <- preprocess_text(df_sample$descriptions)

#print(class(df_sample$salary))
df_sample$salary <- as.numeric(gsub("[^0-9.]", "", df_sample$salary))
# Find entries that caused NAs
problematic_salaries <- df_sample$salary[is.na(as.numeric(gsub("[^0-9.]", "", df_sample$salary)))]
#print(problematic_salaries)

# Define a function to clean salary entries
clean_salary <- function(salary) {
  salary <- gsub(",", "", salary)                # Remove commas
  salary <- gsub("[^0-9.]", "", salary)          # Remove non-numeric characters
  salary <- as.numeric(salary)                  # Convert to numeric
  return(salary)
}

# Apply the function to the salary column
df_sample$salary <- sapply(df_sample$salary, clean_salary)

# Handle NAs after conversion (use median)
df_sample$salary[is.na(df_sample$salary)] <- median(df_sample$salary, na.rm = TRUE)
sum(is.na(df_sample$salary)) # Should be 0 after cleaning



# TF-IDF Vectorization for Text Columns
corpus <- Corpus(VectorSource(c(df_sample$job_title, df_sample$descriptions)))
dtm <- DocumentTermMatrix(corpus)

# Check for and remove empty documents
non_empty_docs <- rowSums(as.matrix(dtm)) > 0
dtm <- dtm[non_empty_docs, ]

# TF-IDF transformation
tfidf_transformer <- weightTfIdf(dtm)
tfidf_matrix <- as.matrix(tfidf_transformer)

# Convert TF-IDF matrix to a data frame
df_tfidf <- as.data.frame(tfidf_matrix)

# Encoding Categorical Columns (if applicable)
categorical_cols <- c("company", "location", "category", "subcategory", "role", "type")
df_encoded <- dummyVars(~ ., data = df_sample[, categorical_cols])
df_categorical <- as.data.frame(predict(df_encoded, df_sample))

# Combine all features into one final data frame
final_data <- cbind(df_tfidf, df_categorical, salary = df_sample$salary)


#write.csv(final_data, "D:\\projects\\da cbp\\processesed_data.csv", row.names = FALSE)


# Step 1: Aggregate Data by Job Field
# Assuming 'category' represents IT job fields
job_demand <- df_sample %>%
  group_by(category) %>%
  summarise(demand = n()) %>%
  arrange(desc(demand)) %>%
  slice_head(n = 10)  # Top 10 job fields

# Step 2: Create a Bar Chart
ggplot(job_demand, aes(x = reorder(category, demand), y = demand, fill = category)) +
  geom_bar(stat = "identity", show.legend = FALSE) +
  coord_flip() +
  labs(
    title = "Top 10 IT Job Fields by Demand",
    x = "Job Field",
    y = "Demand (Number of Job Postings)"
  ) +
  theme_minimal() +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    plot.title = element_text(hjust = 0.5, face = "bold")
  )


# Step 3: Create a Binary Target Variable for High Demand
# Define "high demand" as job fields with demand > median
median_demand <- median(job_demand$demand)
df_sample$high_demand <- ifelse(df_sample$category %in% job_demand$category[job_demand$demand > median_demand], 1, 0)

# Step 4: Prepare Data for Modeling
categorical_cols <- c("company", "location", "role", "type")
df_encoded <- dummyVars(~ ., data = df_sample[, categorical_cols])
df_categorical <- as.data.frame(predict(df_encoded, df_sample))

final_model_data <- cbind(df_categorical, salary = df_sample$salary, high_demand = df_sample$high_demand)
# Clean column names to make them syntactically valid
colnames(final_model_data) <- make.names(colnames(final_model_data), unique = TRUE)

# Re-check the column names
print(colnames(final_model_data))


# Split Data into Training and Test Sets
set.seed(123)
train_index <- createDataPartition(final_model_data$high_demand, p = 0.8, list = FALSE)
train_data <- final_model_data[train_index, ]
test_data <- final_model_data[-train_index, ]

train_data$high_demand <- as.factor(train_data$high_demand)
test_data$high_demand <- as.factor(test_data$high_demand)
library(randomForest)

model_rf <- randomForest(high_demand ~ ., data = train_data, ntree = 100, importance = TRUE)

# Evaluate the Model
predictions <- predict(model_rf, newdata = test_data)
confusionMatrix(predictions, test_data$high_demand)

# Feature Importance
importance <- importance(model_rf)
print(importance)

# Step 5: Predict high demand for all data
df_sample$predicted_high_demand <- predict(model_rf, newdata = final_model_data)

# Step 6: Aggregate predicted high demand by job field (category)
# Step 6: Aggregate predicted high demand by job field (category)
predicted_demand <- df_sample %>%
  group_by(category, predicted_high_demand) %>%
  summarise(count = n()) %>%
  filter(predicted_high_demand == 1) %>%  # Filter for high demand only
  arrange(desc(count))

# Step 7: Create the bar chart based on predicted high demand
ggplot(predicted_demand, aes(x = reorder(category, count), y = count, fill = as.factor(predicted_high_demand))) +
  geom_bar(stat = "identity", position = "dodge") +
  coord_flip() +
  labs(
    title = "Predicted High-Demand Job Fields",
    x = "Job Field",
    y = "Number of Postings"
  ) +
  theme_minimal() +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    plot.title = element_text(hjust = 0.5, face = "bold")
  )

